"""Test data helpers, exposed to Robot as keywords.

A module-level library: every public function becomes a keyword, so
``new_user_payload`` is called from a suite as ``New User Payload``. This is the
place for logic that would be awkward in Robot syntax - generating data,
reshaping payloads, talking to a database - rather than growing a pile of
``Evaluate`` calls in the ``.resource`` files.
"""

from __future__ import annotations

import random
import string
from datetime import datetime, timezone
from typing import Any

__version__ = "0.1.0"

_ADJECTIVES = ("brisk", "calm", "eager", "keen", "lucid", "swift")
_NOUNS = ("otter", "falcon", "cedar", "harbor", "quartz", "meadow")


def random_suffix(length: int = 6) -> str:
    """Return a short lowercase alphanumeric string, for making values unique."""
    alphabet = string.ascii_lowercase + string.digits
    return "".join(random.choices(alphabet, k=length))


def unique_name() -> str:
    """Return a readable, unlikely-to-collide display name."""
    return f"{random.choice(_ADJECTIVES).title()} {random.choice(_NOUNS).title()}"


def unique_email(domain: str = "example.com") -> str:
    """Return an email address that no earlier run will have used."""
    return f"user-{random_suffix()}@{domain}"


def new_user_payload(name: str | None = None, email: str | None = None) -> dict[str, Any]:
    """Build a create-user request body.

    Both fields default to generated values, so a suite can call this with no
    arguments for a valid payload, or override one field to exercise validation:

    | ${payload} = | New User Payload |
    | ${payload} = | New User Payload | email=${EMPTY} |
    """
    return {
        "name": unique_name() if name is None else name,
        "email": unique_email() if email is None else email,
    }


def utc_timestamp() -> str:
    """Return the current UTC time as an ISO 8601 string, for run metadata."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")
