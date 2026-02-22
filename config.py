"""Bot registry — add a new bot by adding one dict entry."""

import os

BOT_HOST = os.environ.get("BOT_HOST", "host.docker.internal")

# Categories for grouping bots in the overview and tab bar
BOT_CATEGORIES = {
    "crypto":  {"label": "Crypto",  "color": "#f7931a"},
    "sports":  {"label": "Sports",  "color": "#58a6ff"},
    "weather": {"label": "Weather", "color": "#4CAF50"},
}

BOTS = {
    "btc-range": {
        "name": "BTC Range Arb",
        "short": "BTC",
        "color": "#f7931a",
        "host": BOT_HOST,
        "port": 5050,
        "health_endpoint": "/api/bot/status",
        "pnl_extractor": "btc_range",
        "category": "crypto",
        "description": "15-min serial correlation mean reversion (S≥4)",
        "auth": None,
    },
    "btc-momentum": {
        "name": "BTC Momentum",
        "short": "MOM",
        "color": "#ff6b6b",
        "host": BOT_HOST,
        "port": 5051,
        "health_endpoint": "/api/bot/status",
        "pnl_extractor": "btc_range",
        "category": "crypto",
        "description": "Extreme momentum continuation (score >0.75)",
        "auth": None,
    },
    "bounce-back": {
        "name": "Bounce-Back",
        "short": "BBK",
        "color": "#06b6d4",
        "host": BOT_HOST,
        "port": 5052,
        "health_endpoint": "/api/status",
        "pnl_extractor": "bounce_back",
        "category": "crypto",
        "description": "Intra-window contract reversal at minute 10 (>8¢ move)",
        "auth": None,
    },
    "fvg-arb": {
        "name": "FVG Arb",
        "short": "FVG",
        "color": "#bc8cff",
        "host": BOT_HOST,
        "port": 5052,
        "health_endpoint": "/api/bot/status",
        "pnl_extractor": "btc_range",
        "category": "crypto",
        "description": "Fair Value Gap mean reversion",
        "auth": None,
    },
    "sports-arb": {
        "name": "Sports Arb",
        "short": "SPT",
        "color": "#58a6ff",
        "host": BOT_HOST,
        "port": 5555,
        "health_endpoint": "/api/health",
        "status_endpoint": "/api/status",
        "pnl_endpoint": "/api/pnl",
        "pnl_extractor": "sports_arb",
        "category": "sports",
        "description": "Real-time odds arbitrage (NBA, Soccer, MLB, NFL, NHL)",
        "auth": {
            "type": "basic",
            "user_env": "SPORTS_DASH_USER",
            "pass_env": "SPORTS_DASH_PASS",
        },
    },
    "weather": {
        "name": "Weather Bot",
        "short": "WX",
        "color": "#4CAF50",
        "host": BOT_HOST,
        "port": 8889,
        "health_endpoint": "/api/data",
        "pnl_extractor": "weather",
        "category": "weather",
        "description": "METAR temperature latency arbitrage",
        "auth": None,
    },
}
