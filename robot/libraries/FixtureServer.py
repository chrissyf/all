"""A throwaway HTTP server used as the system under test.

The scaffold ships with its own target so ``robot tests`` passes on a clean
checkout with no network access and no separate application to boot. Point the
suites at a real deployment by overriding ``${BASE_URL}`` on the command line
(see ``resources/common.resource``); nothing here is imported when you do.

Serves two things:

* an HTML login form at ``/login`` plus a ``/dashboard`` landing page, for the
  ``Browser`` suites in ``tests/web``
* a small JSON user API under ``/api``, for the ``RequestsLibrary`` suites in
  ``tests/api``
"""

from __future__ import annotations

import json
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import parse_qs, urlparse

API_TOKEN = "scaffold-token"
"""Bearer token the ``/api`` routes expect. Not a secret: it exists so the
suites can demonstrate an authenticated session and a 401 path."""

VALID_USERNAME = "demo"
VALID_PASSWORD = "s3cret"

SEED_USERS: list[dict[str, Any]] = [
    {"id": 1, "name": "Ada Lovelace", "email": "ada@example.com"},
    {"id": 2, "name": "Grace Hopper", "email": "grace@example.com"},
]

LOGIN_PAGE = """<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Scaffold - Sign in</title></head>
<body>
  <h1 id="page-heading">Sign in</h1>
  <form id="login-form" method="post" action="/login">
    <label for="username">Username</label>
    <input id="username" name="username" data-testid="username-input" autocomplete="off">
    <label for="password">Password</label>
    <input id="password" name="password" type="password" data-testid="password-input">
    <button id="login-button" data-testid="login-button" type="submit">Sign in</button>
  </form>
  {error}
</body>
</html>
"""

LOGIN_ERROR = '<p id="login-error" data-testid="login-error">Invalid credentials.</p>'

DASHBOARD_PAGE = """<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Scaffold - Dashboard</title></head>
<body>
  <h1 id="welcome-banner" data-testid="welcome-banner">Welcome, {username}!</h1>
  <table id="user-table">
    <thead><tr><th>Name</th><th>Email</th></tr></thead>
    <tbody>{rows}</tbody>
  </table>
  <a id="logout-link" href="/login">Sign out</a>
</body>
</html>
"""


class _Store:
    """In-memory user table, guarded because the server is threaded."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.reset()

    def reset(self) -> None:
        with self._lock:
            self._users = [dict(user) for user in SEED_USERS]
            self._next_id = max((user["id"] for user in self._users), default=0) + 1

    def list(self) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(user) for user in self._users]

    def get(self, user_id: int) -> dict[str, Any] | None:
        with self._lock:
            return next((dict(u) for u in self._users if u["id"] == user_id), None)

    def add(self, name: str, email: str) -> dict[str, Any]:
        with self._lock:
            user = {"id": self._next_id, "name": name, "email": email}
            self._next_id += 1
            self._users.append(user)
            return dict(user)

    def delete(self, user_id: int) -> bool:
        with self._lock:
            remaining = [u for u in self._users if u["id"] != user_id]
            deleted = len(remaining) != len(self._users)
            self._users = remaining
            return deleted


_STORE = _Store()


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ------------------------------------------------------------- helpers ---
    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        """Silence the default stderr access log so it stays out of the run."""

    def _respond(self, status: HTTPStatus, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _html(self, status: HTTPStatus, markup: str) -> None:
        self._respond(status, markup.encode("utf-8"), "text/html; charset=utf-8")

    def _json(self, status: HTTPStatus, payload: Any) -> None:
        self._respond(status, json.dumps(payload).encode("utf-8"), "application/json")

    def _authorized(self) -> bool:
        return self.headers.get("Authorization") == f"Bearer {API_TOKEN}"

    def _read_json(self) -> Any:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return None
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return None

    def _read_form(self) -> dict[str, str]:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        return {key: values[0] for key, values in parse_qs(raw).items()}

    # -------------------------------------------------------------- routes ---
    def do_GET(self) -> None:  # noqa: N802 - name mandated by BaseHTTPRequestHandler
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path in ("/", "/login"):
            self._html(HTTPStatus.OK, LOGIN_PAGE.format(error=""))
        elif path == "/dashboard":
            username = parse_qs(parsed.query).get("user", ["guest"])[0]
            rows = "".join(
                f"<tr><td>{u['name']}</td><td>{u['email']}</td></tr>" for u in _STORE.list()
            )
            self._html(HTTPStatus.OK, DASHBOARD_PAGE.format(username=username, rows=rows))
        elif path == "/api/health":
            self._json(HTTPStatus.OK, {"status": "ok"})
        elif path == "/api/users":
            self._api_list_users()
        elif path.startswith("/api/users/"):
            self._api_get_user(path)
        else:
            self._json(HTTPStatus.NOT_FOUND, {"error": f"No route for {path}"})

    def do_POST(self) -> None:  # noqa: N802 - name mandated by BaseHTTPRequestHandler
        path = urlparse(self.path).path.rstrip("/") or "/"
        if path == "/login":
            self._submit_login()
        elif path == "/api/users":
            self._api_create_user()
        else:
            self._json(HTTPStatus.NOT_FOUND, {"error": f"No route for {path}"})

    def do_DELETE(self) -> None:  # noqa: N802 - name mandated by BaseHTTPRequestHandler
        path = urlparse(self.path).path.rstrip("/") or "/"
        if not path.startswith("/api/users/"):
            self._json(HTTPStatus.NOT_FOUND, {"error": f"No route for {path}"})
            return
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid bearer token"})
            return
        user_id = self._user_id_from(path)
        if user_id is None or not _STORE.delete(user_id):
            self._json(HTTPStatus.NOT_FOUND, {"error": "User not found"})
            return
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ----------------------------------------------------------- handlers ---
    def _submit_login(self) -> None:
        form = self._read_form()
        if form.get("username") == VALID_USERNAME and form.get("password") == VALID_PASSWORD:
            self.send_response(HTTPStatus.SEE_OTHER)
            self.send_header("Location", f"/dashboard?user={VALID_USERNAME}")
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self._html(HTTPStatus.UNAUTHORIZED, LOGIN_PAGE.format(error=LOGIN_ERROR))

    def _api_list_users(self) -> None:
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid bearer token"})
            return
        users = _STORE.list()
        self._json(HTTPStatus.OK, {"users": users, "count": len(users)})

    def _api_get_user(self, path: str) -> None:
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid bearer token"})
            return
        user_id = self._user_id_from(path)
        user = _STORE.get(user_id) if user_id is not None else None
        if user is None:
            self._json(HTTPStatus.NOT_FOUND, {"error": "User not found"})
            return
        self._json(HTTPStatus.OK, user)

    def _api_create_user(self) -> None:
        if not self._authorized():
            self._json(HTTPStatus.UNAUTHORIZED, {"error": "Missing or invalid bearer token"})
            return
        payload = self._read_json()
        if not isinstance(payload, dict):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "Body must be a JSON object"})
            return
        missing = [field for field in ("name", "email") if not payload.get(field)]
        if missing:
            self._json(HTTPStatus.BAD_REQUEST, {"error": f"Missing fields: {', '.join(missing)}"})
            return
        self._json(HTTPStatus.CREATED, _STORE.add(payload["name"], payload["email"]))

    @staticmethod
    def _user_id_from(path: str) -> int | None:
        try:
            return int(path.rsplit("/", 1)[-1])
        except ValueError:
            return None


class FixtureServer:
    """Robot library that owns the lifetime of the fixture HTTP server.

    Global scope on purpose: one server is shared by every suite in a run, so
    ``tests/web`` and ``tests/api`` do not fight over a port.
    """

    ROBOT_LIBRARY_SCOPE = "GLOBAL"
    ROBOT_LIBRARY_VERSION = "0.1.0"

    def __init__(self) -> None:
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None

    def start_fixture_server(self, host: str = "127.0.0.1") -> str:
        """Start the fixture server if it is not already running.

        Returns the base URL, e.g. ``http://127.0.0.1:54321``. Binding to port 0
        lets the OS pick a free port, so parallel runs do not collide. Calling
        this twice is a no-op that returns the already running server's URL.
        """
        if self._server is None:
            self._server = ThreadingHTTPServer((host, 0), _Handler)
            self._thread = threading.Thread(
                target=self._server.serve_forever,
                name="robot-fixture-server",
                daemon=True,
            )
            self._thread.start()
        host, port = self._server.server_address[:2]
        return f"http://{host}:{port}"

    def stop_fixture_server(self) -> None:
        """Shut the fixture server down. Safe to call when it is not running."""
        if self._server is None:
            return
        self._server.shutdown()
        self._server.server_close()
        if self._thread is not None:
            self._thread.join(timeout=5)
        self._server = None
        self._thread = None

    def reset_fixture_data(self) -> None:
        """Restore the seeded users, undoing anything the tests created."""
        _STORE.reset()

    def fixture_api_token(self) -> str:
        """Return the bearer token the fixture ``/api`` routes accept."""
        return API_TOKEN
