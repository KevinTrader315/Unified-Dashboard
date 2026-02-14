"""Unified portal — proxies to per-bot dashboards and aggregates overview."""

import os
import re
import requests
from flask import Flask, request, Response, jsonify, render_template

from config import BOTS, BOT_HOST

app = Flask(__name__)

PROXY_TIMEOUT = 5  # seconds


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _bot_base(bot_id: str) -> str:
    """Return the base URL for a bot."""
    return f"http://{BOT_HOST}:{BOTS[bot_id]['port']}"


def _bot_auth(bot_id: str):
    """Return (user, password) tuple or None."""
    cfg = BOTS[bot_id].get("auth")
    if not cfg:
        return None
    user = os.environ.get(cfg["user_env"], "")
    pw = os.environ.get(cfg["pass_env"], "")
    if user and pw:
        return (user, pw)
    return None


def _proxy(bot_id: str, path: str):
    """Forward the current request to the bot and return the response."""
    url = f"{_bot_base(bot_id)}/{path}"
    headers = {k: v for k, v in request.headers if k.lower() not in
                ("host", "connection", "transfer-encoding")}
    try:
        resp = requests.request(
            method=request.method,
            url=url,
            headers=headers,
            params=request.args,
            data=request.get_data(),
            auth=_bot_auth(bot_id),
            timeout=PROXY_TIMEOUT,
            allow_redirects=False,
        )
        excluded = {"transfer-encoding", "connection", "content-encoding", "content-length"}
        fwd_headers = [(k, v) for k, v in resp.headers.items()
                       if k.lower() not in excluded]
        return Response(resp.content, status=resp.status_code, headers=fwd_headers)
    except requests.RequestException:
        return jsonify({"error": "Bot unreachable", "bot": bot_id}), 502


# ---------------------------------------------------------------------------
# Generic proxy route — any bot endpoint is automatically forwarded
# ---------------------------------------------------------------------------

@app.route("/proxy/<bot_id>/", defaults={"path": ""}, methods=["GET", "POST", "PUT", "DELETE"])
@app.route("/proxy/<bot_id>/<path:path>", methods=["GET", "POST", "PUT", "DELETE"])
def proxy_route(bot_id, path):
    if bot_id not in BOTS:
        return jsonify({"error": f"Unknown bot: {bot_id}"}), 404
    return _proxy(bot_id, path)


# ---------------------------------------------------------------------------
# Bot dashboard injection — fetch root HTML, inject fetch interceptor
# ---------------------------------------------------------------------------

_INTERCEPT_TEMPLATE = """
<script>
(function() {{
    var _origFetch = window.fetch;
    window.fetch = function(url, opts) {{
        if (typeof url === 'string' && url.startsWith('/api'))
            url = '/proxy/{bot_id}' + url;
        return _origFetch.call(this, url, opts);
    }};
    var _origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url) {{
        if (typeof url === 'string' && url.startsWith('/api'))
            url = '/proxy/{bot_id}' + url;
        return _origOpen.apply(this, arguments);
    }};
}})();
</script>
"""


@app.route("/bot/<bot_id>/")
def bot_dashboard(bot_id):
    if bot_id not in BOTS:
        return jsonify({"error": f"Unknown bot: {bot_id}"}), 404
    try:
        resp = requests.get(
            _bot_base(bot_id) + "/",
            auth=_bot_auth(bot_id),
            timeout=PROXY_TIMEOUT,
        )
        html = resp.text
        intercept = _INTERCEPT_TEMPLATE.format(bot_id=bot_id)
        # Inject right after <head> (or at start if no <head>)
        if re.search(r"<head[^>]*>", html, re.IGNORECASE):
            html = re.sub(r"(<head[^>]*>)", r"\1" + intercept, html, count=1, flags=re.IGNORECASE)
        else:
            html = intercept + html
        return Response(html, content_type="text/html")
    except requests.RequestException:
        return f"<html><body style='background:#0a0e14;color:#f44;font-family:monospace;padding:2rem'>" \
               f"<h2>{BOTS[bot_id]['name']} is unreachable</h2>" \
               f"<p>The bot at port {BOTS[bot_id]['port']} is not responding.</p></body></html>", 502


# ---------------------------------------------------------------------------
# Overview aggregation
# ---------------------------------------------------------------------------

def _extract_weather(data):
    pt = data.get("paper_trading", {})
    lt = data.get("live_trading", {})
    armed = lt.get("armed", False)
    realized = pt.get("realized_pnl", 0) / 100.0
    balance = pt.get("current_balance", 0) / 100.0
    starting = pt.get("starting_balance", 0) / 100.0
    total_pnl = balance - starting
    return {
        "healthy": True,
        "mode": "LIVE" if armed else "PAPER",
        "pnl": round(total_pnl, 2),
        "realized_pnl": round(realized, 2),
        "open_positions": pt.get("open_positions_count", 0),
        "daily_trades": pt.get("daily_trades", 0),
    }


def _extract_btc_range(data):
    pnl_sum = data.get("pnl_summary", {})
    return {
        "healthy": True,
        "mode": data.get("mode", "unknown").upper(),
        "running": data.get("running", False),
        "pnl": round(pnl_sum.get("total_pnl", 0), 2),
        "win_rate": round(pnl_sum.get("win_rate", 0) * 100, 1),
        "completed": pnl_sum.get("completed", 0),
        "wins": pnl_sum.get("wins", 0),
    }


def _extract_sports_arb_health(data):
    return {
        "healthy": data.get("status") == "healthy",
        "bot_running": data.get("bot_running", False),
        "ws_connected": data.get("websocket_connected", False),
    }


def _extract_sports_arb_status(data):
    pnl_sum = data.get("pnl_summary", {})
    bot_st = data.get("bot_status", {})
    return {
        "mode": "LIVE" if not bot_st.get("dry_run", True) else "DRY RUN",
        "pnl": round(pnl_sum.get("total_pnl", 0) / 100.0, 2),
        "win_rate": round(pnl_sum.get("win_rate", 0) * 100, 1),
        "completed": pnl_sum.get("completed", 0),
        "wins": pnl_sum.get("wins", 0),
        "status": bot_st.get("status", "unknown"),
    }


@app.route("/api/overview")
def overview():
    results = {}
    for bot_id, cfg in BOTS.items():
        entry = {"name": cfg["name"], "short": cfg["short"], "color": cfg["color"],
                 "healthy": False, "mode": "UNKNOWN", "pnl": 0}
        try:
            health_url = _bot_base(bot_id) + cfg["health_endpoint"]
            resp = requests.get(health_url, auth=_bot_auth(bot_id), timeout=PROXY_TIMEOUT)
            resp.raise_for_status()
            data = resp.json()

            extractor = cfg.get("pnl_extractor")
            if extractor == "weather":
                entry.update(_extract_weather(data))
            elif extractor == "btc_range":
                entry.update(_extract_btc_range(data))
            elif extractor == "sports_arb":
                entry.update(_extract_sports_arb_health(data))
                # Sports arb health endpoint doesn't have P&L; fetch status
                try:
                    status_url = _bot_base(bot_id) + cfg.get("status_endpoint", "/api/status")
                    sr = requests.get(status_url, auth=_bot_auth(bot_id), timeout=PROXY_TIMEOUT)
                    sr.raise_for_status()
                    entry.update(_extract_sports_arb_status(sr.json()))
                except requests.RequestException:
                    pass
        except requests.RequestException:
            entry["error"] = "Unreachable"
        results[bot_id] = entry

    total_pnl = sum(b.get("pnl", 0) for b in results.values())
    return jsonify({"bots": results, "total_pnl": round(total_pnl, 2)})


# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    return render_template("portal.html", bots=BOTS)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
