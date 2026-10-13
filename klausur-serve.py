#!/usr/bin/env python3
"""Hand every visitor exactly one exam paper and pin it with a cookie.

The papers are served from a read-only Nix store path (see klausur.nix).  A
visitor with no (or an unusable) cookie gets the next paper in round-robin
order, so all papers are handed out equally often; the choice is then stored in
a cookie, so a reload or a later visit always yields the same paper.  The
cookie holds an HMAC of the paper's file name instead of the file name itself,
so a visitor cannot tamper with it to pick a different paper.

Environment, set by the systemd unit:
  KLAUSUR_EXAM_DIR   directory with the exam PDFs
  KLAUSUR_PORT       port to listen on (bound to 127.0.0.1, Caddy proxies it)
  STATE_DIRECTORY    writable state dir (systemd StateDirectory=)
"""

from __future__ import annotations

import hashlib
import hmac
import http.cookies
import http.server
import os
import pathlib
import secrets
import sys
import threading

EXAM_DIR = pathlib.Path(os.environ["KLAUSUR_EXAM_DIR"])
STATE_DIR = pathlib.Path(os.environ["STATE_DIRECTORY"])
PORT = int(os.environ["KLAUSUR_PORT"])
COOKIE_NAME = os.environ.get("KLAUSUR_COOKIE_NAME", "klausur")
COOKIE_MAX_AGE = int(os.environ.get("KLAUSUR_COOKIE_MAX_AGE", f"{60 * 60 * 24 * 365}"))

COUNTER_FILE = STATE_DIR / "assignments"
SECRET_FILE = STATE_DIR / "secret"


def load_secret() -> bytes:
    """The per-installation secret that signs assignment cookies."""
    try:
        secret = SECRET_FILE.read_bytes().strip()
        if len(secret) >= 32:
            return secret
    except FileNotFoundError:
        pass
    secret = secrets.token_bytes(32)
    SECRET_FILE.write_bytes(secret)
    SECRET_FILE.chmod(0o600)
    return secret


class Exams:
    """The available papers plus the round-robin bookkeeping."""

    def __init__(self, directory: pathlib.Path) -> None:
        self.directory = directory
        self.secret = load_secret()
        self.lock = threading.Lock()
        self.papers = sorted(
            path
            for path in directory.iterdir()
            if path.is_file() and path.suffix.lower() == ".pdf"
        )

    def token(self, paper: pathlib.Path) -> str:
        """Opaque cookie value for a paper; unforgeable without the secret."""
        return hmac.new(self.secret, paper.name.encode(), hashlib.sha256).hexdigest()

    def paper_for_token(self, token: str) -> pathlib.Path | None:
        for paper in self.papers:
            if hmac.compare_digest(token, self.token(paper)):
                return paper
        return None

    def next_paper(self) -> pathlib.Path:
        """Round-robin: every paper is handed out before any paper repeats."""
        with self.lock:
            handed_out = self.read_counter()
            self.write_counter(handed_out + 1)
            return self.papers[handed_out % len(self.papers)]

    def read_counter(self) -> int:
        try:
            return int(COUNTER_FILE.read_text().strip() or "0")
        except (FileNotFoundError, ValueError):
            return 0

    def write_counter(self, value: int) -> None:
        tmp = COUNTER_FILE.with_name(COUNTER_FILE.name + ".tmp")
        tmp.write_text(f"{value}\n")
        tmp.replace(COUNTER_FILE)  # atomic; a crash cannot leave a partial count


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "klausur"
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        self.respond(send_body=True)

    def do_HEAD(self) -> None:
        self.respond(send_body=False)

    def respond(self, send_body: bool) -> None:
        exams: Exams = self.server.exams  # ty: ignore[unresolved-attribute]

        if self.path.split("?", 1)[0] not in ("", "/"):
            self.send_error(404)
            return

        if not exams.papers:
            self.send_text(503, "no exam papers configured yet\n", send_body)
            return

        cookie = self.read_cookie()
        paper = exams.paper_for_token(cookie) if cookie else None
        assignment = None
        if paper is None:
            paper = exams.next_paper()
            assignment = exams.token(paper)
            self.log_message("assigned %s", paper.name)

        data = paper.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", "application/pdf")
        self.send_header("Content-Length", str(len(data)))
        # the URL is "/" for everybody, so nothing may cache one visitor's paper
        # and hand it to the next one
        self.send_header("Cache-Control", "no-store, private")
        self.send_header("Vary", "Cookie")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        if assignment is not None:
            self.send_header("Set-Cookie", self.cookie_header(assignment))
        self.end_headers()
        if send_body:
            self.wfile.write(data)

    def read_cookie(self) -> str:
        jar = http.cookies.SimpleCookie()
        try:
            jar.load(self.headers.get("Cookie", ""))
        except http.cookies.CookieError:
            return ""
        morsel = jar.get(COOKIE_NAME)
        return morsel.value if morsel else ""

    @staticmethod
    def cookie_header(token: str) -> str:
        return (
            f"{COOKIE_NAME}={token}; Path=/; Max-Age={COOKIE_MAX_AGE}; "
            "SameSite=Lax; Secure; HttpOnly"
        )

    def send_text(self, code: int, message: str, send_body: bool = True) -> None:
        body = message.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if send_body:
            self.wfile.write(body)


class ExamServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    # a whole exam room may knock at the same time; the default backlog is 5
    request_queue_size = 128

    def __init__(self, address: tuple[str, int], exams: Exams) -> None:
        self.exams = exams
        super().__init__(address, Handler)


def main() -> None:
    if not EXAM_DIR.is_dir():
        sys.exit(f"exam directory {EXAM_DIR} is missing")
    exams = Exams(EXAM_DIR)
    print(f"klausur: {len(exams.papers)} paper(s) in {EXAM_DIR}", flush=True)
    for paper in exams.papers:
        print(f"klausur:   {paper.name}", flush=True)
    server = ExamServer(("127.0.0.1", PORT), exams)
    print(f"klausur: listening on http://127.0.0.1:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
