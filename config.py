"""Bot registry — add a new bot by adding one dict entry."""

import os

BOT_HOST = os.environ.get("BOT_HOST", "host.docker.internal")

BOTS = {
    "weather": {
        "name": "Weather Bot",
        "short": "WX",
        "color": "#4CAF50",
        "port": 8889,
        "health_endpoint": "/api/data",
        "pnl_extractor": "weather",
        "auth": None,
    },
    "btc-range": {
        "name": "BTC Range Arb",
        "short": "BTC",
        "color": "#f7931a",
        "port": 5050,
        "health_endpoint": "/api/bot/status",
        "pnl_extractor": "btc_range",
        "auth": None,
    },
    "sports-arb": {
        "name": "Sports Arb",
        "short": "SPT",
        "color": "#58a6ff",
        "port": 5555,
        "health_endpoint": "/api/health",
        "status_endpoint": "/api/status",
        "pnl_endpoint": "/api/pnl",
        "pnl_extractor": "sports_arb",
        "auth": {
            "type": "basic",
            "user_env": "SPORTS_DASH_USER",
            "pass_env": "SPORTS_DASH_PASS",
        },
    },
}
