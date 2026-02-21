"""Unified portal — proxies to per-bot dashboards and aggregates overview."""

import json
import logging
import os
import re
import secrets
import subprocess
import threading
import time

import paramiko
import requests
from flask import Flask, request, Response, jsonify, render_template
from flask_sock import Sock
from functools import wraps

from config import BOTS, BOT_HOST

logger = logging.getLogger(__name__)

app = Flask(__name__)
sock = Sock(app)

PROXY_TIMEOUT = 5  # seconds

PORTAL_USER = os.environ.get("PORTAL_USER", "")
PORTAL_PASS = os.environ.get("PORTAL_PASS", "")
AUTH_ENABLED = bool(PORTAL_USER and PORTAL_PASS)


def _auth_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not AUTH_ENABLED:
            return f(*args, **kwargs)
        auth = request.authorization
        if not auth or auth.username != PORTAL_USER or auth.password != PORTAL_PASS:
            return Response("Unauthorized", 401,
                            {"WWW-Authenticate": 'Basic realm="Kalshi Portal"'})
        return f(*args, **kwargs)
    return decorated


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _bot_base(bot_id: str) -> str:
    """Return the base URL for a bot."""
    host = BOTS[bot_id].get("host", BOT_HOST)
    return f"http://{host}:{BOTS[bot_id]['port']}"


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
        # Some endpoints (e.g. /api/fills) paginate Kalshi API and take longer
        slow_paths = ('fills', 'settlements')
        effective_timeout = 60 if any(path.endswith(p) for p in slow_paths) else PROXY_TIMEOUT
        resp = requests.request(
            method=request.method,
            url=url,
            headers=headers,
            params=request.args,
            data=request.get_data(),
            auth=_bot_auth(bot_id),
            timeout=effective_timeout,
            allow_redirects=False,
        )
        excluded = {"transfer-encoding", "connection", "content-encoding", "content-length"}
        fwd_headers = [(k, v) for k, v in resp.headers.items()
                       if k.lower() not in excluded]
        return Response(resp.content, status=resp.status_code, headers=fwd_headers)
    except requests.RequestException as e:
        logger.error("Proxy to %s failed: %s %s", bot_id, type(e).__name__, e)
        return jsonify({"error": "Bot unreachable", "bot": bot_id}), 502


# ---------------------------------------------------------------------------
# Generic proxy route — any bot endpoint is automatically forwarded
# ---------------------------------------------------------------------------

@app.route("/proxy/<bot_id>/", defaults={"path": ""}, methods=["GET", "POST", "PUT", "DELETE"])
@app.route("/proxy/<bot_id>/<path:path>", methods=["GET", "POST", "PUT", "DELETE"])
@_auth_required
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

    // --- Capital allocation banner ---
    var _botId = '{bot_id}';
    var _botColor = '{bot_color}';

    function _fmtDollars(cents) {{
        var abs = Math.abs(cents) / 100;
        var s = '$' + abs.toFixed(2);
        return cents < 0 ? '-' + s : s;
    }}

    function _updateCapitalBanner() {{
        _origFetch.call(window, '/api/capital').then(function(r) {{
            return r.json();
        }}).then(function(data) {{
            var acct = null;
            (data.accounts || []).forEach(function(a) {{
                if (a.id === _botId) acct = a;
            }});

            var banner = document.getElementById('portal-capital-banner');
            if (!banner) {{
                banner = document.createElement('div');
                banner.id = 'portal-capital-banner';
                banner.style.cssText = 'position:fixed;top:0;left:0;right:0;height:32px;z-index:999999;'
                    + 'display:flex;align-items:center;font-family:monospace;font-size:12px;'
                    + 'background:#0d1117;color:#c9d1d9;border-bottom:1px solid #21262d;'
                    + 'border-left:3px solid ' + _botColor + ';padding:0 12px;gap:16px;';
                document.body.prepend(banner);
                document.body.style.paddingTop = '32px';
            }}

            if (!acct) {{
                banner.innerHTML = '<span style="color:#8b949e">No capital allocated &mdash; configure in Portal &gt; Capital tab</span>';
                return;
            }}

            var pnlColor = acct.pnl >= 0 ? '#3fb950' : '#f85149';
            var pnlSign = acct.pnl >= 0 ? '+' : '';
            banner.innerHTML =
                '<span style="color:#8b949e">ALLOCATED:</span> <span style="color:#e6edf3;font-weight:bold">' + _fmtDollars(acct.allocation) + '</span>'
                + '<span style="color:#8b949e;margin-left:12px">P&amp;L:</span> <span style="color:' + pnlColor + ';font-weight:bold">' + pnlSign + _fmtDollars(acct.pnl) + '</span>'
                + '<span style="color:#8b949e;margin-left:12px">EFFECTIVE:</span> <span style="color:#e6edf3;font-weight:bold">' + _fmtDollars(acct.effective) + '</span>';
        }}).catch(function() {{}});
    }}

    if (document.readyState === 'loading') {{
        document.addEventListener('DOMContentLoaded', _updateCapitalBanner);
    }} else {{
        _updateCapitalBanner();
    }}
    setInterval(_updateCapitalBanner, 30000);
}})();
</script>
"""


@app.route("/bot/<bot_id>/")
@_auth_required
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
        bot_color = BOTS[bot_id].get("color", "#888")
        intercept = _INTERCEPT_TEMPLATE.format(bot_id=bot_id, bot_color=bot_color)
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

def _extract_bounce_back(data):
    summary = data.get("summary", {})
    return {
        "healthy": data.get("running", False),
        "running": data.get("running", False),
        "mode": (data.get("mode") or "PAPER").upper(),
        "pnl": round(summary.get("total_pnl", 0), 3),
        "completed": summary.get("settled", 0),
        "wins": summary.get("wins", 0),
        "win_rate": round(summary.get("win_rate", 0) * 100, 1),
        "open_positions": summary.get("open", 0),
    }


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
@_auth_required
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
            elif extractor == "bounce_back":
                entry.update(_extract_bounce_back(data))
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
        except requests.RequestException as e:
            logger.error("Overview health check for %s failed: %s %s", bot_id, type(e).__name__, e)
            entry["error"] = "Unreachable"
        results[bot_id] = entry

    total_pnl = sum(b.get("pnl", 0) for b in results.values())
    return jsonify({"bots": results, "total_pnl": round(total_pnl, 2)})


# ---------------------------------------------------------------------------
# Capital management (virtual ledger)
# ---------------------------------------------------------------------------

_kalshi_client = None
_capital_store = None


def _get_kalshi_client():
    global _kalshi_client
    if _kalshi_client is None:
        api_key = os.environ.get("KALSHI_API_KEY")
        pk_path = os.environ.get("KALSHI_PRIVATE_KEY_PATH")
        if api_key and pk_path:
            from kalshi_client import KalshiClient
            _kalshi_client = KalshiClient(api_key, pk_path)
    return _kalshi_client


def _get_capital_store():
    global _capital_store
    if _capital_store is None:
        from subaccount_store import CapitalStore
        _capital_store = CapitalStore()
    return _capital_store


def _get_bot_pnl():
    """Fetch P&L for each bot (in dollars). Returns {bot_id: pnl_dollars}."""
    pnl = {}
    for bot_id, cfg in BOTS.items():
        try:
            health_url = _bot_base(bot_id) + cfg["health_endpoint"]
            resp = requests.get(health_url, auth=_bot_auth(bot_id), timeout=PROXY_TIMEOUT)
            resp.raise_for_status()
            data = resp.json()
            extractor = cfg.get("pnl_extractor")
            if extractor == "weather":
                pnl[bot_id] = _extract_weather(data).get("pnl", 0)
            elif extractor == "btc_range":
                pnl[bot_id] = _extract_btc_range(data).get("pnl", 0)
            elif extractor == "bounce_back":
                pnl[bot_id] = _extract_bounce_back(data).get("pnl", 0)
            elif extractor == "sports_arb":
                try:
                    status_url = _bot_base(bot_id) + cfg.get("status_endpoint", "/api/status")
                    sr = requests.get(status_url, auth=_bot_auth(bot_id), timeout=PROXY_TIMEOUT)
                    sr.raise_for_status()
                    pnl[bot_id] = _extract_sports_arb_status(sr.json()).get("pnl", 0)
                except requests.RequestException:
                    pnl[bot_id] = 0
        except requests.RequestException:
            pnl[bot_id] = 0
    return pnl


@app.route("/api/capital", methods=["GET"])
@_auth_required
def get_capital():
    """Return virtual accounts merged with real Kalshi balance and bot P&L."""
    store = _get_capital_store()
    accounts = store.get_accounts()
    total_allocated = store.get_total_allocated()

    # Real Kalshi balance (cents), None if creds not set
    real_balance = None
    client = _get_kalshi_client()
    if client:
        try:
            real_balance = client.get_balance()
        except Exception as e:
            logger.warning("Failed to fetch Kalshi balance: %s", e)

    # Bot P&L
    bot_pnl = _get_bot_pnl()

    # Build account list
    account_list = []
    for bot_id, acct in accounts.items():
        alloc = acct.get("allocation", 0)
        pnl_dollars = bot_pnl.get(bot_id, 0)
        pnl_cents = int(round(pnl_dollars * 100))
        color = BOTS[bot_id]["color"] if bot_id in BOTS else "#888"
        account_list.append({
            "id": bot_id,
            "label": acct.get("label", bot_id),
            "allocation": alloc,
            "pnl": pnl_cents,
            "effective": alloc + pnl_cents,
            "color": color,
        })

    unallocated = (real_balance - total_allocated) if real_balance is not None else None

    return jsonify({
        "real_balance": real_balance,
        "total_allocated": total_allocated,
        "unallocated": unallocated,
        "accounts": account_list,
    })


@app.route("/api/capital/allocate", methods=["POST"])
@_auth_required
def allocate_capital():
    """Create or update a virtual allocation. Amount is in dollars."""
    data = request.get_json(force=True)
    bot_id = data.get("bot_id", "").strip()
    label = data.get("label", "").strip()
    amount = data.get("amount")
    if not bot_id:
        return jsonify({"error": "bot_id is required"}), 400
    if not label:
        return jsonify({"error": "label is required"}), 400
    if amount is None or float(amount) < 0:
        return jsonify({"error": "amount must be >= 0"}), 400
    try:
        amount_cents = int(round(float(amount) * 100))
        _get_capital_store().allocate(bot_id, label, amount_cents)
        return jsonify({"ok": True})
    except Exception as e:
        logger.exception("Allocate failed")
        return jsonify({"error": str(e)}), 500


@app.route("/api/capital/<bot_id>", methods=["DELETE"])
@_auth_required
def remove_capital(bot_id):
    """Remove a virtual allocation."""
    try:
        _get_capital_store().remove(bot_id)
        return jsonify({"ok": True})
    except Exception as e:
        logger.exception("Remove failed")
        return jsonify({"error": str(e)}), 500


@app.route("/api/capital/transfer", methods=["POST"])
@_auth_required
def transfer_capital():
    """Transfer between virtual accounts. Amount is in dollars."""
    data = request.get_json(force=True)
    from_id = data.get("from", "").strip()
    to_id = data.get("to", "").strip()
    amount = data.get("amount")
    if not from_id or not to_id:
        return jsonify({"error": "from and to are required"}), 400
    if amount is None or float(amount) <= 0:
        return jsonify({"error": "amount must be positive"}), 400
    try:
        amount_cents = int(round(float(amount) * 100))
        _get_capital_store().transfer(from_id, to_id, amount_cents)
        return jsonify({"ok": True})
    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.exception("Transfer failed")
        return jsonify({"error": str(e)}), 500


@app.route("/api/capital/<bot_id>/limit", methods=["GET"])
@_auth_required
def get_capital_limit(bot_id):
    """Lightweight endpoint for bots to query their allocation.

    Returns {"allocation_cents": N} or {"allocation_cents": null} if
    the bot has no entry in capital.json.  No P&L or health calls.
    """
    store = _get_capital_store()
    accounts = store.get_accounts()
    acct = accounts.get(bot_id)
    if acct is None:
        return jsonify({"allocation_cents": None})
    return jsonify({"allocation_cents": acct.get("allocation", 0)})


@app.route("/api/capital/transfers", methods=["GET"])
@_auth_required
def get_capital_transfers():
    """Return recent transfer history."""
    limit = request.args.get("limit", 20, type=int)
    try:
        transfers = _get_capital_store().get_transfers(limit=limit)
        return jsonify({"transfers": transfers})
    except Exception as e:
        logger.exception("Failed to fetch transfers")
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Claude Code integration
# ---------------------------------------------------------------------------

CLAUDE_ENABLED = os.environ.get("CLAUDE_ENABLED", "1") == "1"
CLAUDE_WORK_DIR = os.environ.get("CLAUDE_WORK_DIR",
                                  os.path.dirname(os.path.abspath(__file__)))
CLAUDE_MAX_TURNS = int(os.environ.get("CLAUDE_MAX_TURNS", "10"))

_claude_lock = threading.Lock()


@app.route("/api/claude", methods=["POST"])
@_auth_required
def claude_chat():
    """Run a Claude Code prompt and stream results via SSE."""
    if not CLAUDE_ENABLED:
        return jsonify({"error": "Claude Code integration is disabled. "
                        "Set CLAUDE_ENABLED=1 to enable."}), 403

    data = request.get_json(force=True)
    prompt = data.get("prompt", "").strip()
    session_id = data.get("session_id", "").strip()
    if not prompt:
        return jsonify({"error": "prompt is required"}), 400

    if not _claude_lock.acquire(blocking=False):
        return jsonify({"error": "Another Claude request is already running. "
                        "Please wait for it to finish."}), 429

    def generate():
        proc = None
        try:
            cmd = [
                "claude", "-p",
                "--output-format", "stream-json",
                "--verbose",
                "--max-turns", str(CLAUDE_MAX_TURNS),
                "--allowedTools",
                "Bash(curl:*)", "Bash(git:*)",
                "Read", "Edit", "Write", "Glob", "Grep",
            ]
            # Resume a previous conversation if session_id is provided
            if session_id:
                cmd += ["--resume", session_id]
            cmd += ["--", prompt]
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=CLAUDE_WORK_DIR,
                text=True,
                bufsize=1,
            )
            for line in proc.stdout:
                line = line.strip()
                if line:
                    yield f"data: {line}\n\n"
            proc.wait(timeout=300)
            if proc.returncode != 0:
                err = proc.stderr.read()
                yield f"data: {json.dumps({'type': 'error', 'error': err})}\n\n"
            yield "data: [DONE]\n\n"
        except FileNotFoundError:
            yield ("data: " + json.dumps({
                "type": "error",
                "error": "claude CLI not found. "
                         "Install: npm install -g @anthropic-ai/claude-code"
            }) + "\n\n")
            yield "data: [DONE]\n\n"
        except subprocess.TimeoutExpired:
            if proc:
                proc.kill()
            yield ("data: " + json.dumps({
                "type": "error",
                "error": "Request timed out (5 min limit)"
            }) + "\n\n")
            yield "data: [DONE]\n\n"
        except GeneratorExit:
            pass
        except Exception as e:
            yield f"data: {json.dumps({'type': 'error', 'error': str(e)})}\n\n"
            yield "data: [DONE]\n\n"
        finally:
            if proc and proc.poll() is None:
                proc.kill()
            _claude_lock.release()

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ---------------------------------------------------------------------------
# System info
# ---------------------------------------------------------------------------

@app.route("/api/system")
@_auth_required
def api_system():
    """Return Docker container statuses, cron jobs, and host resource usage."""
    import shutil

    # Docker containers — query via Docker socket API
    containers = []
    try:
        import http.client, urllib.parse
        conn = http.client.HTTPConnection("localhost")
        conn.sock = __import__('socket').socket(__import__('socket').AF_UNIX, __import__('socket').SOCK_STREAM)
        conn.sock.connect("/var/run/docker.sock")
        conn.request("GET", "/containers/json?all=true")
        resp = conn.getresponse()
        raw = json.loads(resp.read())
        for c in raw:
            name = c.get("Names", ["?"])[0].lstrip("/")
            status = c.get("Status", "")
            image = c.get("Image", "")
            running = c.get("State", "") == "running"
            ports_list = c.get("Ports", [])
            port_str = ", ".join(
                f"{p.get('PublicPort','?')}→{p.get('PrivatePort','?')}"
                for p in ports_list if p.get("PublicPort")
            ) or "—"
            bot_meta = next((
                {"id": bid, "color": b.get("color","#888"), "description": b.get("description","")}
                for bid, b in BOTS.items() if b.get("host","") == name
            ), None)
            containers.append({
                "name": name, "status": status, "ports": port_str,
                "image": image, "running": running, "bot": bot_meta,
            })
        conn.close()
    except Exception as e:
        containers = [{"error": str(e)}]

    # Cron jobs
    cron_jobs = [
        {"schedule": "*/5 * * * *",  "label": "Memory Watchdog",        "script": "memory_watchdog.sh",                "description": "Monitors RAM; alerts Discord at 80%/90%, auto-restarts at 95%"},
        {"schedule": "*/15 * * * *", "label": "Sports Status Report",   "script": "sports-arb/status_report.sh",        "description": "Periodic sports-arb health snapshot"},
        {"schedule": "59 7 * * *",   "label": "BTC Data → Google Drive","script": "btc-range-arb/sync_to_gdrive.sh",    "description": "Daily upload of window_summary.jsonl to Google Drive (08:00 UTC)"},
        {"schedule": "59 7 * * *",   "label": "Sports Scoring → Drive", "script": "sports-arb/sync_scoring_to_gdrive.sh","description": "Daily upload of sports scoring data to Google Drive (08:00 UTC)"},
    ]

    # Infrastructure services — infer from what's reachable inside container
    import socket as _socket
    services = []
    # Docker: active if we successfully talked to the socket above
    services.append({"name": "docker", "active": not any("error" in c for c in containers)})
    # nginx: try TCP connect to host port 80
    try:
        s = _socket.create_connection(("host.docker.internal", 80), timeout=2)
        s.close()
        services.append({"name": "nginx", "active": True})
    except Exception:
        services.append({"name": "nginx", "active": False})

    # Host resources
    mem_info = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":")
                mem_info[k.strip()] = int(v.strip().split()[0])
        total_mb = mem_info.get("MemTotal", 0) // 1024
        avail_mb = mem_info.get("MemAvailable", 0) // 1024
        used_mb  = total_mb - avail_mb
    except Exception:
        total_mb = used_mb = avail_mb = 0

    disk = {}
    try:
        usage = shutil.disk_usage("/")
        disk = {
            "total_gb": round(usage.total / 1e9, 1),
            "used_gb":  round(usage.used  / 1e9, 1),
            "free_gb":  round(usage.free  / 1e9, 1),
            "pct":      round(usage.used / usage.total * 100, 1),
        }
    except Exception:
        pass

    return jsonify({
        "containers": containers,
        "cron_jobs":  cron_jobs,
        "services":   services,
        "resources":  {"mem_total_mb": total_mb, "mem_used_mb": used_mb, "mem_avail_mb": avail_mb, "disk": disk},
    })


# ---------------------------------------------------------------------------
# SSH Terminal
# ---------------------------------------------------------------------------

SSH_HOST = os.environ.get("SSH_HOST", BOT_HOST)
SSH_PORT = int(os.environ.get("SSH_PORT", "22"))
SSH_USER = os.environ.get("SSH_USER", "")
SSH_PASSWORD = os.environ.get("SSH_PASSWORD", "")
SSH_KEY_PATH = os.environ.get("SSH_KEY_PATH", "")

# Short-lived tokens for WebSocket authentication
_ws_tokens = {}  # token -> expiry timestamp
_ws_tokens_lock = threading.Lock()


def _clean_expired_tokens():
    now = time.time()
    expired = [t for t, exp in _ws_tokens.items() if exp < now]
    for t in expired:
        _ws_tokens.pop(t, None)


def _issue_ws_token():
    with _ws_tokens_lock:
        _clean_expired_tokens()
        token = secrets.token_urlsafe(32)
        _ws_tokens[token] = time.time() + 600  # 10 min expiry
        return token


def _validate_ws_token(token):
    with _ws_tokens_lock:
        exp = _ws_tokens.get(token)
        if exp and exp > time.time():
            return True
        return False


@app.route("/terminal")
@_auth_required
def terminal_page():
    token = _issue_ws_token()
    return render_template(
        "terminal.html",
        ws_token=token,
        ssh_host=SSH_HOST,
        ssh_port=SSH_PORT,
        ssh_user=SSH_USER,
        has_default_auth=bool(SSH_PASSWORD or SSH_KEY_PATH),
    )


@app.route("/terminal/token")
@_auth_required
def terminal_token():
    return jsonify({"token": _issue_ws_token()})


@sock.route("/terminal/ws")
def terminal_ws(ws):
    """WebSocket handler: relay between browser and SSH session."""
    # Validate token from query string
    token = request.args.get("token", "")
    if AUTH_ENABLED and not _validate_ws_token(token):
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": "Unauthorized — reload the page"}))
        return

    # Wait for connect message
    try:
        raw = ws.receive(timeout=30)
        if raw is None:
            return
        msg = json.loads(raw)
    except Exception:
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": "Invalid connect message"}))
        return

    if msg.get("type") != "connect":
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": "Expected connect message"}))
        return

    host = msg.get("host", SSH_HOST) or SSH_HOST
    port = int(msg.get("port", SSH_PORT) or SSH_PORT)
    username = msg.get("username", SSH_USER) or SSH_USER

    # Determine auth method
    password = None
    pkey = None
    if msg.get("use_default_auth"):
        password = SSH_PASSWORD or None
        if SSH_KEY_PATH and os.path.isfile(SSH_KEY_PATH):
            try:
                pkey = paramiko.RSAKey.from_private_key_file(SSH_KEY_PATH)
            except Exception:
                try:
                    pkey = paramiko.Ed25519Key.from_private_key_file(SSH_KEY_PATH)
                except Exception:
                    pass
    else:
        password = msg.get("password") or None

    if not username:
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": "Username is required"}))
        return

    # Establish SSH connection
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        connect_kwargs = {
            "hostname": host,
            "port": port,
            "username": username,
            "timeout": 10,
            "allow_agent": False,
            "look_for_keys": False,
        }
        if pkey:
            connect_kwargs["pkey"] = pkey
        elif password:
            connect_kwargs["password"] = password
        else:
            connect_kwargs["look_for_keys"] = True
            connect_kwargs["allow_agent"] = True
        client.connect(**connect_kwargs)
    except paramiko.AuthenticationException:
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": "Authentication failed — check credentials"}))
        client.close()
        return
    except Exception as e:
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": f"SSH connection failed: {e}"}))
        client.close()
        return

    # Open interactive shell
    try:
        channel = client.invoke_shell(
            term="xterm-256color",
            width=80,
            height=24,
        )
        channel.settimeout(0.1)
    except Exception as e:
        ws.send(json.dumps({"type": "status", "status": "error",
                            "message": f"Failed to open shell: {e}"}))
        client.close()
        return

    ws.send(json.dumps({"type": "status", "status": "connected",
                        "message": f"Connected to {username}@{host}"}))

    # SSH -> WebSocket reader thread
    stop_event = threading.Event()

    def ssh_reader():
        try:
            while not stop_event.is_set():
                if channel.recv_ready():
                    data = channel.recv(4096)
                    if not data:
                        break
                    try:
                        ws.send(json.dumps({
                            "type": "output",
                            "data": data.decode("utf-8", errors="replace"),
                        }))
                    except Exception:
                        break
                elif channel.closed:
                    break
                else:
                    time.sleep(0.02)
        except Exception:
            pass
        finally:
            try:
                ws.send(json.dumps({"type": "status", "status": "disconnected"}))
            except Exception:
                pass

    reader = threading.Thread(target=ssh_reader, daemon=True)
    reader.start()

    # WebSocket -> SSH writer loop (runs in this thread)
    try:
        while not stop_event.is_set():
            raw = ws.receive(timeout=1)
            if raw is None:
                break
            try:
                msg = json.loads(raw)
            except Exception:
                continue
            if msg.get("type") == "input":
                data = msg.get("data", "")
                if data and not channel.closed:
                    channel.sendall(data.encode("utf-8"))
            elif msg.get("type") == "resize":
                cols = int(msg.get("cols", 80))
                rows = int(msg.get("rows", 24))
                if not channel.closed:
                    channel.resize_pty(width=cols, height=rows)
    except Exception:
        pass
    finally:
        stop_event.set()
        try:
            channel.close()
        except Exception:
            pass
        try:
            client.close()
        except Exception:
            pass
        reader.join(timeout=2)


# ---------------------------------------------------------------------------
# Index
# ---------------------------------------------------------------------------

@app.route("/")
@_auth_required
def index():
    from config import BOT_CATEGORIES
    return render_template("portal.html", bots=BOTS, categories=BOT_CATEGORIES)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
