"""Virtual capital ledger — per-bot allocations and transfer log."""

import fcntl
import json
import os
from datetime import datetime, timezone

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
STORE_PATH = os.path.join(DATA_DIR, "capital.json")


class CapitalStore:
    """Persistent virtual capital allocations and transfer history.

    File format (data/capital.json):
        {
          "accounts": {
            "btc-range": {"label": "BTC Range", "allocation": 500000},
            ...
          },
          "transfers": [
            {"from": "unallocated", "to": "btc-range", "amount": 500000, "ts": "..."},
            ...
          ]
        }

    Amounts are in cents (matching Kalshi internal format).
    """

    def __init__(self, path=None):
        self.path = path or STORE_PATH
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        if not os.path.exists(self.path):
            self._write({"accounts": {}, "transfers": []})

    def _read(self):
        with open(self.path, "r") as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                data = {"accounts": {}, "transfers": []}
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)
        # Ensure expected keys
        data.setdefault("accounts", {})
        data.setdefault("transfers", [])
        return data

    def _write(self, data):
        with open(self.path, "w") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            try:
                json.dump(data, f, indent=2)
            finally:
                fcntl.flock(f, fcntl.LOCK_UN)

    def get_accounts(self):
        """Return dict of all virtual accounts: {bot_id: {label, allocation}, ...}"""
        return self._read()["accounts"]

    def allocate(self, bot_id, label, amount_cents):
        """Create or update a virtual allocation for a bot.

        Args:
            bot_id: Bot identifier (e.g. "btc-range")
            label: Display label (e.g. "BTC Range")
            amount_cents: Allocation amount in cents
        """
        data = self._read()
        old_amount = data["accounts"].get(bot_id, {}).get("allocation", 0)
        data["accounts"][bot_id] = {"label": label, "allocation": int(amount_cents)}
        # Log the allocation change as a transfer
        diff = int(amount_cents) - old_amount
        if diff != 0:
            data["transfers"].append({
                "from": "unallocated" if diff > 0 else bot_id,
                "to": bot_id if diff > 0 else "unallocated",
                "amount": abs(diff),
                "ts": datetime.now(timezone.utc).isoformat(),
            })
        self._write(data)

    def transfer(self, from_id, to_id, amount_cents):
        """Transfer between virtual accounts. Adjusts allocations and logs.

        Args:
            from_id: Source account (bot_id or "unallocated")
            to_id: Destination account (bot_id or "unallocated")
            amount_cents: Amount in cents (must be positive)
        """
        amount_cents = int(amount_cents)
        if amount_cents <= 0:
            raise ValueError("amount must be positive")
        if from_id == to_id:
            raise ValueError("from and to must differ")

        data = self._read()
        accounts = data["accounts"]

        # Deduct from source (skip if unallocated — it's implicit)
        if from_id != "unallocated":
            if from_id not in accounts:
                raise ValueError(f"account '{from_id}' not found")
            accounts[from_id]["allocation"] -= amount_cents

        # Add to destination (skip if unallocated)
        if to_id != "unallocated":
            if to_id not in accounts:
                raise ValueError(f"account '{to_id}' not found")
            accounts[to_id]["allocation"] += amount_cents

        data["transfers"].append({
            "from": from_id,
            "to": to_id,
            "amount": amount_cents,
            "ts": datetime.now(timezone.utc).isoformat(),
        })
        self._write(data)

    def get_transfers(self, limit=20):
        """Return recent transfer history (newest first)."""
        transfers = self._read()["transfers"]
        return list(reversed(transfers[-limit:]))

    def remove(self, bot_id):
        """Remove a virtual account. Allocation returns to unallocated pool."""
        data = self._read()
        removed = data["accounts"].pop(bot_id, None)
        if removed and removed.get("allocation", 0) != 0:
            data["transfers"].append({
                "from": bot_id,
                "to": "unallocated",
                "amount": removed["allocation"],
                "ts": datetime.now(timezone.utc).isoformat(),
            })
        self._write(data)

    def get_total_allocated(self):
        """Return sum of all allocations in cents."""
        return sum(a.get("allocation", 0) for a in self._read()["accounts"].values())
