"""Kalshi API client — balance queries with RSA-PSS signing."""

import base64
import logging
import requests
from datetime import datetime, timezone
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

logger = logging.getLogger(__name__)

API_BASE = "https://api.elections.kalshi.com/trade-api/v2"


class KalshiClient:
    """Handles Kalshi API authentication and balance queries."""

    def __init__(self, api_key, private_key_path):
        self.api_key = api_key
        with open(private_key_path, 'rb') as f:
            self.private_key = serialization.load_pem_private_key(f.read(), password=None)
        self.session = requests.Session()

    def _sign(self, method, path):
        """Create signed headers for Kalshi API v2."""
        timestamp = str(int(datetime.now(timezone.utc).timestamp() * 1000))
        message = f"{timestamp}{method}{path.split('?')[0]}"
        signature = self.private_key.sign(
            message.encode(),
            padding.PSS(
                mgf=padding.MGF1(hashes.SHA256()),
                salt_length=hashes.SHA256().digest_size,
            ),
            hashes.SHA256(),
        )
        return {
            'KALSHI-ACCESS-KEY': self.api_key,
            'KALSHI-ACCESS-SIGNATURE': base64.b64encode(signature).decode(),
            'KALSHI-ACCESS-TIMESTAMP': timestamp,
            'Content-Type': 'application/json',
        }

    def _request(self, method, path):
        """Make a signed request to Kalshi API. Returns parsed JSON or raises."""
        url = f"{API_BASE}{path}"
        headers = self._sign(method, f"/trade-api/v2{path}")
        resp = self.session.request(method, url, headers=headers, timeout=15)
        if not resp.ok:
            try:
                err = resp.json().get("error", {})
                msg = err.get("message", resp.text) if isinstance(err, dict) else str(err)
            except Exception:
                msg = resp.text
            raise RuntimeError(f"Kalshi API {resp.status_code}: {msg}")
        return resp.json() if resp.content else {}

    def get_balance(self):
        """Get primary account balance in cents."""
        data = self._request("GET", "/portfolio/balance")
        return data.get("balance", 0)
