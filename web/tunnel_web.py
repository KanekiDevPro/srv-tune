#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""temper tunnel web panel.

Loopback HTTP frontend over the `temper tunnel ... --json` CLI.
Standard library only. The panel never edits sshd policy: it shows
status/sessions/keys and can add or remove tunnel keys.

Auth: one login URL with the token from <state>/web/token, then an
HttpOnly SameSite=Strict cookie. Mutations are POST only and require a
CSRF value derived from the token. Failed token logins are rate limited
per client IP.
"""
import argparse
import hashlib
import hmac
import html
import json
import os
import re
import secrets
import subprocess
import sys
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

FP_RE = re.compile(r"^SHA256:[A-Za-z0-9+/=]+$")
TOKEN_MIN = 32
RATE_LIMIT = 5
RATE_WINDOW = 60.0
MAX_BODY = 64 * 1024

LABELS = {
    "en": {
        "title": "temper tunnel",
        "status": "Status",
        "mode": "mode",
        "port": "port",
        "user": "user",
        "permit_open": "PermitOpen",
        "gateway_ports": "GatewayPorts",
        "permit_tunnel": "PermitTunnel",
        "ip_forward": "ip_forward",
        "dropin": "drop-in",
        "sessions": "Sessions",
        "peer": "Peer",
        "pid": "PID",
        "keys": "Keys",
        "fp": "Fingerprint",
        "type": "Type",
        "comment": "Comment",
        "remove": "Remove",
        "add": "Add key",
        "key": "Public key",
        "no_sessions": "No active sessions",
        "no_keys": "No keys",
        "login": "Login required: open the token URL printed by `temper tunnel web`.",
    },
    "fa": {
        "title": "تونل temper",
        "status": "وضعیت",
        "mode": "حالت",
        "port": "پورت",
        "user": "کاربر",
        "permit_open": "PermitOpen",
        "gateway_ports": "GatewayPorts",
        "permit_tunnel": "PermitTunnel",
        "ip_forward": "ip_forward",
        "dropin": "drop-in",
        "sessions": "نشست‌ها",
        "peer": "مقصد",
        "pid": "PID",
        "keys": "کلیدها",
        "fp": "اثر انگشت",
        "type": "نوع",
        "comment": "توضیح",
        "remove": "حذف",
        "add": "افزودن کلید",
        "key": "کلید عمومی",
        "no_sessions": "نشست فعالی نیست",
        "no_keys": "کلیدی نیست",
        "login": "ورود لازم است: URL توکن را که `temper tunnel web` چاپ می‌کند باز کنید.",
    },
}


def cookie_for(token):
    return hmac.new(token.encode("utf-8"), b"cookie", hashlib.sha256).hexdigest()


def csrf_for(token):
    return hmac.new(token.encode("utf-8"), b"csrf", hashlib.sha256).hexdigest()


def is_loopback(addr):
    return addr == "localhost" or addr == "::1" or addr.startswith("127.")


def parse_form(raw):
    return parse_qs(raw.decode("utf-8"), keep_blank_values=True)


def port_type(value):
    try:
        port = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("port must be an integer")
    if port < 1 or port > 65535:
        raise argparse.ArgumentTypeError("port must be 1-65535")
    return port


def load_token(state_dir):
    webdir = os.path.join(state_dir, "web")
    os.makedirs(webdir, mode=0o700, exist_ok=True)
    path = os.path.join(webdir, "token")
    if os.path.exists(path):
        check_token_mode(path)
        with open(path, "r", encoding="utf-8") as fh:
            token = fh.read().strip()
        if len(token) < TOKEN_MIN or any(c not in "0123456789abcdef" for c in token):
            sys.exit("error: token file is malformed: %s" % path)
        return token
    token = secrets.token_hex(16)
    fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.write(fd, (token + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    check_token_mode(path)
    return token


def check_token_mode(path):
    # POSIX only: Windows reports 0666/0777 regardless of chmod, so a mode
    # check there would reject every token file.
    if os.name != "posix":
        return
    mode = os.stat(path).st_mode & 0o777
    if mode & 0o077:
        sys.exit("error: token file is group/world readable: %s" % path)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "temper-tunnel-web"

    def log_message(self, fmt, *args):
        # Never log the request line: it can contain the login token.
        return

    # ---- transport helpers -------------------------------------------------

    def _respond(self, code, body, ctype="text/plain; charset=utf-8", extra=None):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        for name, value in extra or ():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _json(self, code, obj):
        self._respond(code, json.dumps(obj, separators=(",", ":")) + "\n",
                      "application/json; charset=utf-8")

    def _redirect(self, location, extra=None):
        self._respond(303, b"", extra=[("Location", location)] + list(extra or []))

    # ---- connection state --------------------------------------------------

    def _client(self):
        return self.client_address[0]

    def _st_cookie(self):
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            name, _, value = part.strip().partition("=")
            if name == "st":
                return value
        return ""

    def _authed(self):
        got = self._st_cookie()
        return bool(got) and hmac.compare_digest(
            got.encode("utf-8", "replace"), self.server.cookie.encode("ascii")
        )

    def _lang(self):
        query = parse_qs(urlsplit(self.path).query)
        wanted = (query.get("lang") or [""])[0]
        if wanted in LABELS:
            return wanted
        raw = self.headers.get("Cookie", "")
        for part in raw.split(";"):
            name, _, value = part.strip().partition("=")
            if name == "lang" and value in LABELS:
                return value
        return self.server.lang

    def _rate_limited(self):
        now = time.time()
        fails = self.server.failures[self._client()]
        while fails and now - fails[0] > RATE_WINDOW:
            fails.popleft()
        return len(fails) >= RATE_LIMIT

    def _record_failure(self):
        self.server.failures[self._client()].append(time.time())

    # ---- CLI bridge --------------------------------------------------------

    def _cli(self, args, stdin=None):
        env = dict(os.environ)
        env["TEMPER_ACTOR"] = "web"
        env["TEMPER_SRC"] = self._client()
        try:
            proc = subprocess.run(
                [self.server.cli] + args,
                input=stdin,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                env=env,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return "", 1, "cli failed: %s" % exc
        return (
            proc.stdout.decode("utf-8", "replace").strip(),
            proc.returncode,
            proc.stderr.decode("utf-8", "replace").strip(),
        )

    def _json_call(self, args):
        out, rc, err = self._cli(args)
        if rc != 0:
            return None, err or out or ("cli failed (rc=%d)" % rc)
        try:
            return json.loads(out), ""
        except ValueError:
            return None, "cli returned invalid JSON"

    # ---- GET ---------------------------------------------------------------

    def do_GET(self):
        if self._rate_limited():
            return self._respond(429, "too many failed logins; retry in a minute\n")
        url = urlsplit(self.path)
        if url.path == "/":
            return self._root(url)
        if url.path in ("/api/status", "/api/sessions", "/api/keys"):
            return self._api_get(url.path)
        if url.path in ("/api/keys/add", "/api/keys/remove"):
            return self._respond(405, "method not allowed\n", extra=[("Allow", "POST")])
        return self._respond(404, "not found\n")

    def _root(self, url):
        query = parse_qs(url.query)
        token = (query.get("token") or [""])[0]
        if token:
            if not hmac.compare_digest(
                token.encode("utf-8", "replace"), self.server.token.encode("ascii")
            ):
                # Only login attempts count toward the rate limit, so a
                # stale cookie cannot lock out the auto-refreshing dashboard.
                self._record_failure()
                return self._respond(401, "bad token\n")
            extra = [
                ("Set-Cookie", "st=%s; HttpOnly; SameSite=Strict; Path=/"
                 % self.server.cookie),
            ]
            lang = (query.get("lang") or [""])[0]
            if lang in LABELS:
                extra.append(
                    ("Set-Cookie", "lang=%s; SameSite=Strict; Path=/" % lang)
                )
                return self._redirect("/?lang=%s" % lang, extra)
            return self._redirect("/", extra)
        if not self._authed():
            return self._respond(401, LABELS[self.server.lang]["login"] + "\n")
        return self._page()

    def _api_get(self, path):
        if not self._authed():
            return self._respond(401, "login required\n")
        sub = path.rsplit("/", 1)[1]
        out, rc, err = self._cli(["tunnel", sub, "--json"])
        if rc != 0:
            return self._json(400 if rc == 2 else 500,
                              {"ok": False, "error": err or "cli failed"})
        try:
            payload = json.loads(out)
        except ValueError:
            return self._json(500, {"ok": False, "error": "cli returned invalid JSON"})
        return self._respond(200, json.dumps(payload, separators=(",", ":")) + "\n",
                             "application/json; charset=utf-8")

    def _page(self):
        lang = self._lang()
        labels = LABELS[lang]
        status, status_err = self._json_call(["tunnel", "status", "--json"])
        sessions, _ = self._json_call(["tunnel", "sessions", "--json"])
        keys, keys_err = self._json_call(["tunnel", "keys", "list", "--json"])
        error = status_err or keys_err
        status = status or {}
        session_rows = (sessions or {}).get("sessions") or []
        key_rows = (keys or {}).get("keys") or []
        csrf = self.server.csrf

        status_rows = ""
        for field in ("mode", "port", "user", "permit_open", "gateway_ports",
                      "permit_tunnel", "ip_forward", "dropin", "sessions"):
            value = status.get(field, "?")
            status_rows += (
                "<tr><th>%s</th><td>%s</td></tr>"
                % (html.escape(labels.get(field, field)),
                   html.escape(str(value)))
            )

        sessions_html = ""
        if session_rows:
            for row in session_rows:
                sessions_html += (
                    "<tr><td>%s</td><td>%s</td></tr>"
                    % (html.escape(str(row.get("peer", ""))),
                       html.escape(str(row.get("pid", ""))))
                )
            sessions_html = (
                "<table><tr><th>%s</th><th>%s</th></tr>%s</table>"
                % (labels["peer"], labels["pid"], sessions_html)
            )
        else:
            sessions_html = "<p>%s</p>" % labels["no_sessions"]

        keys_html = ""
        if key_rows:
            rows = ""
            for key in key_rows:
                fp = str(key.get("fp", ""))
                rows += (
                    "<tr><td><code>%s</code></td><td>%s</td><td>%s</td>"
                    "<td><form method=\"post\" action=\"/api/keys/remove\">"
                    "<input type=\"hidden\" name=\"csrf\" value=\"%s\">"
                    "<input type=\"hidden\" name=\"fp\" value=\"%s\">"
                    "<button type=\"submit\">%s</button></form></td></tr>"
                    % (html.escape(fp),
                       html.escape(str(key.get("type", ""))),
                       html.escape(str(key.get("comment", ""))),
                       html.escape(csrf), html.escape(fp),
                       html.escape(labels["remove"]))
                )
            keys_html = (
                "<table><tr><th>%s</th><th>%s</th><th>%s</th><th></th></tr>%s</table>"
                % (labels["fp"], labels["type"], labels["comment"], rows)
            )
        else:
            keys_html = "<p>%s</p>" % labels["no_keys"]

        add_form = (
            "<form method=\"post\" action=\"/api/keys/add\">"
            "<input type=\"hidden\" name=\"csrf\" value=\"%s\">"
            "<p><label>%s<br><textarea name=\"key\" rows=\"3\" cols=\"80\" required></textarea></label></p>"
            "<p><label>%s <input name=\"comment\" size=\"30\"></label> "
            "<button type=\"submit\">%s</button></p></form>"
            % (html.escape(csrf), html.escape(labels["key"]),
               html.escape(labels["comment"]), html.escape(labels["add"]))
        )

        banner = ""
        if error:
            banner = "<p class=err>%s</p>" % html.escape(error)

        page = """<!doctype html>
<html lang="%(lang)s" dir="%(dir)s">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="10">
<title>%(title)s</title>
<style>
body{font:15px/1.5 system-ui,sans-serif;max-width:60rem;margin:2rem auto;padding:0 1rem;color:#1b1b1b}
h1{font-size:1.3rem}h2{font-size:1.05rem;margin-top:1.6rem}
table{border-collapse:collapse;width:100%%}th,td{text-align:start;padding:.25rem .5rem;border-bottom:1px solid #ddd}
th{font-weight:600}code{font-size:.85em}.err{background:#ffe8e8;padding:.5rem;border:1px solid #d88}
textarea{width:100%%;font-family:ui-monospace,monospace}
</style>
</head>
<body>
<h1>%(title)s</h1>
%(banner)s
<h2>%(status)s</h2>
<table id="status">%(status_rows)s</table>
<h2>%(sessions)s</h2>
%(sessions_html)s
<h2>%(keys)s</h2>
%(keys_html)s
%(add_form)s
</body>
</html>
""" % {
            "lang": lang,
            "dir": "rtl" if lang == "fa" else "ltr",
            "title": html.escape(labels["title"]),
            "banner": banner,
            "status": html.escape(labels["status"]),
            "status_rows": status_rows,
            "sessions": html.escape(labels["sessions"]),
            "sessions_html": sessions_html,
            "keys": html.escape(labels["keys"]),
            "keys_html": keys_html,
            "add_form": add_form,
        }
        return self._respond(200, page, "text/html; charset=utf-8")

    # ---- POST --------------------------------------------------------------

    def do_POST(self):
        if self._rate_limited():
            return self._respond(429, "too many failed logins; retry in a minute\n")
        url = urlsplit(self.path)
        if url.path in ("/api/status", "/api/sessions", "/api/keys", "/"):
            return self._respond(405, "method not allowed\n", extra=[("Allow", "GET")])
        if url.path not in ("/api/keys/add", "/api/keys/remove"):
            return self._respond(404, "not found\n")
        if not self._authed():
            return self._respond(401, "login required\n")
        parsed = self._read_body()
        if parsed is None:
            return None
        payload, csrf, form = parsed
        if not hmac.compare_digest(
            csrf.encode("utf-8", "replace"), self.server.csrf.encode("ascii")
        ):
            return self._respond(403, "csrf check failed\n")
        if url.path == "/api/keys/add":
            return self._keys_add(payload, form)
        return self._keys_remove(payload, form)

    def _read_body(self):
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        try:
            length = int(self.headers.get("Content-Length") or "0")
        except ValueError:
            self._respond(400, "bad content length\n")
            return None
        if length < 0 or length > MAX_BODY:
            self._respond(413, "body too large\n")
            return None
        raw = self.rfile.read(length) if length else b""
        if ctype == "application/json":
            try:
                payload = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                self._respond(400, "bad json\n")
                return None
            if not isinstance(payload, dict):
                self._respond(400, "json object required\n")
                return None
            return payload, self.headers.get("X-CSRF", ""), False
        if ctype in ("application/x-www-form-urlencoded", ""):
            try:
                fields = parse_form(raw)
            except UnicodeDecodeError:
                self._respond(400, "bad form encoding\n")
                return None
            payload = {name: values[0] for name, values in fields.items()}
            return payload, payload.get("csrf", ""), True
        self._respond(415, "unsupported content type\n")
        return None

    def _keys_add(self, payload, form):
        key = str(payload.get("key", "")).strip()
        comment = str(payload.get("comment", "")).strip()
        if not key:
            return self._answer(form, 400, "key is required")
        args = ["tunnel", "keys", "add"]
        if comment:
            args += ["--comment", comment]
        out, rc, err = self._cli(args, stdin=(key + "\n").encode("utf-8"))
        return self._mutation_reply(form, rc, out, err)

    def _keys_remove(self, payload, form):
        fp = str(payload.get("fp", "")).strip()
        if not FP_RE.match(fp):
            return self._answer(form, 400, "bad fingerprint")
        out, rc, err = self._cli(["tunnel", "keys", "remove", "--fp", fp])
        return self._mutation_reply(form, rc, out, err)

    def _mutation_reply(self, form, rc, out, err):
        if rc == 0:
            if form:
                return self._redirect("/")
            return self._json(200, {"ok": True, "message": out})
        message = err or out or "command failed"
        return self._answer(form, 400 if rc == 2 else 500, message)

    def _answer(self, form, code, message):
        if form:
            return self._respond(code, "error: %s\n" % message)
        return self._json(code, {"ok": False, "error": message})


def self_check():
    assert cookie_for("a") == cookie_for("a")
    assert cookie_for("a") != cookie_for("b")
    assert csrf_for("a") != cookie_for("a")
    assert FP_RE.match("SHA256:abc+/=")
    assert not FP_RE.match("SHA256:abc def")
    assert not FP_RE.match("MD5:abc")
    assert is_loopback("127.0.0.1")
    assert is_loopback("::1")
    assert not is_loopback("0.0.0.0")
    assert parse_form(b"csrf=x&key=a%20b")["key"] == ["a b"]
    print("self-check ok")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="temper tunnel web panel (loopback, token auth)")
    parser.add_argument("--port", type=port_type, default=8787)
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--state-dir", default="")
    parser.add_argument("--bin", default="temper")
    parser.add_argument("--lang", choices=sorted(LABELS), default="en")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args(argv)

    if args.self_check:
        return self_check()
    if not args.state_dir:
        parser.error("--state-dir is required")

    token = load_token(args.state_dir)
    if not is_loopback(args.bind):
        print("warning: binding %s is reachable off-host; prefer ssh -L %s:127.0.0.1:%s"
              % (args.bind, args.port, args.port), file=sys.stderr)

    try:
        server = ThreadingHTTPServer((args.bind, args.port), Handler)
    except OSError as exc:
        print("error: cannot bind %s:%s: %s" % (args.bind, args.port, exc),
              file=sys.stderr)
        return 1
    server.daemon_threads = True
    server.token = token
    server.cookie = cookie_for(token)
    server.csrf = csrf_for(token)
    server.cli = args.bin
    server.lang = args.lang
    server.failures = defaultdict(deque)

    print("tunnel web: open http://%s:%s/?token=%s once to log in"
          % (args.bind, args.port, token), flush=True)
    print("tunnel web: Ctrl+C stops the panel", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
