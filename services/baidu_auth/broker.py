"""Baidu OAuth broker. Bind loopback behind the authenticated Nginx vhost."""
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class Fault(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def credential(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43,128}', value):
        raise Fault(400, 'invalid_credential')
    return value


class Limits:
    def __init__(self, clock=time.monotonic):
        self.clock, self.lock, self.items = clock, threading.Lock(), OrderedDict()

    def take(self, key, limit, seconds=60):
        with self.lock:
            now = self.clock()
            while self.items and next(iter(self.items.values()))[0] <= now:
                self.items.popitem(last=False)
            expiry, count = self.items.get(key, (now + seconds, 0))
            if expiry <= now:
                expiry, count = now + seconds, 0
            if count >= limit or (key not in self.items and len(self.items) >= 4096):
                raise Fault(429, 'rate_limited')
            self.items[key] = (expiry, count + 1)
            # Expiry-based sorting keeps cleanup bounded and independent of access order.
            self.items = OrderedDict(sorted(self.items.items(), key=lambda x: x[1][0]))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Broker:
    callback_path = '/oauth/baidu/callback'

    def __init__(self, database, key, app_key, app_secret, origin, exchange=None):
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS pending (
          state TEXT PRIMARY KEY, proof TEXT NOT NULL, expires REAL NOT NULL,
          status TEXT NOT NULL, payload BLOB);
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY, expires REAL NOT NULL, payload BLOB NOT NULL);
        ''')
        self.lock = threading.RLock()
        self.cipher = AESGCM(key)
        self.app_key, self.app_secret, self.origin = app_key, app_secret, origin
        self.exchange = exchange or self._exchange
        self.limits = Limits()
        self.upstream = threading.BoundedSemaphore(4)
        self.refresh_locks = [threading.Lock() for _ in range(64)]

    def seal(self, data, context):
        nonce = secrets.token_bytes(12)
        return nonce + self.cipher.encrypt(nonce, json.dumps(data).encode(), context.encode())

    def open(self, data, context):
        return json.loads(self.cipher.decrypt(data[:12], data[12:], context.encode()))

    def _exchange(self, fields):
        body = urllib.parse.urlencode(dict(fields, client_id=self.app_key,
                                          client_secret=self.app_secret)).encode()
        req = urllib.request.Request('https://openapi.baidu.com/oauth/2.0/token', data=body,
                                     headers={'Content-Type': 'application/x-www-form-urlencoded'})
        try:
            with urllib.request.build_opener(NoRedirect).open(req, timeout=10) as response:
                data = response.read(65537)
            if len(data) > 65536:
                raise Fault(502, 'invalid_upstream_response')
            result = json.loads(data)
        except urllib.error.HTTPError as error:
            # Never include upstream response bodies or credential-bearing URLs in logs.
            if error.code in (400, 401):
                raise Fault(401, 'reauthorize') from None
            raise Fault(502, 'baidu_unavailable') from None
        except (OSError, ValueError):
            raise Fault(502, 'baidu_unavailable') from None
        if not isinstance(result, dict):
            raise Fault(502, 'invalid_upstream_response')
        if result.get('error'):
            raise Fault(401, 'reauthorize')
        return result

    def tokens(self, fields):
        self.limits.take('upstream', 30)
        if not self.upstream.acquire(blocking=False):
            raise Fault(503, 'busy')
        try:
            result = self.exchange(fields)
            if not isinstance(result, dict):
                raise Fault(502, 'invalid_upstream_response')
            if not all(isinstance(result.get(k), str) and 0 < len(result[k]) < 8192
                       for k in ('access_token', 'refresh_token')):
                raise Fault(502, 'invalid_upstream_response')
            expires = result.get('expires_in')
            if not isinstance(expires, int) or isinstance(expires, bool) or expires <= 0:
                raise Fault(502, 'invalid_upstream_response')
            return dict(access_token=result['access_token'], refresh_token=result['refresh_token'],
                        expires_at=time.time() + expires)
        finally:
            self.upstream.release()

    def cleanup(self):
        now = time.time()
        self.db.execute('DELETE FROM pending WHERE expires < ?', (now,))
        self.db.execute('DELETE FROM sessions WHERE expires < ?', (now,))

    def start(self, challenge, ip):
        if not isinstance(challenge, str) or not re.fullmatch('[a-f0-9]{64}', challenge):
            raise Fault(400, 'invalid_challenge')
        self.limits.take('login:' + ip, 5)
        state = secrets.token_urlsafe(32)
        with self.lock, self.db:
            self.cleanup()
            if self.db.execute('SELECT COUNT(*) FROM pending').fetchone()[0] >= 1000:
                raise Fault(503, 'busy')
            self.db.execute('INSERT INTO pending VALUES (?,?,?,?,NULL)',
                            (digest(state), challenge, time.time() + 300, 'waiting'))
        query = urllib.parse.urlencode(dict(response_type='code', client_id=self.app_key,
                       redirect_uri=self.origin + self.callback_path, scope='basic,netdisk',
                       state=state))
        return dict(ticket=state, authorize_url='https://openapi.baidu.com/oauth/2.0/authorize?' + query)

    def callback(self, state, code, denied=False):
        key = digest(credential(state))
        with self.lock, self.db:
            self.cleanup()
            row = self.db.execute('SELECT status FROM pending WHERE state=?', (key,)).fetchone()
            if not row or row[0] != 'waiting':
                raise Fault(400, 'expired_authorization')
            self.db.execute('UPDATE pending SET status=? WHERE state=?', ('exchanging', key))
        try:
            if denied:
                raise Fault(401, 'authorization_denied')
            if not isinstance(code, str) or not 1 <= len(code) <= 2048:
                raise Fault(400, 'invalid_code')
            tokens = self.tokens(dict(grant_type='authorization_code', code=code,
                                     redirect_uri=self.origin + self.callback_path))
            with self.lock, self.db:
                self.db.execute('UPDATE pending SET status=?,payload=? WHERE state=?',
                                ('ready', self.seal(tokens, key), key))
        except Fault as error:
            with self.lock, self.db:
                self.db.execute('UPDATE pending SET status=? WHERE state=?', ('failed', key))
            raise error

    def claim(self, ticket, proof):
        key = digest(credential(ticket))
        proof = digest(credential(proof))
        self.limits.take('claim:' + key, 15)
        with self.lock, self.db:
            self.cleanup()
            row = self.db.execute('SELECT proof,status,payload FROM pending WHERE state=?', (key,)).fetchone()
            if not row or not hmac.compare_digest(row[0], proof):
                raise Fault(401, 'invalid_authorization')
            if row[1] in ('waiting', 'exchanging'):
                return dict(pending=True)
            if row[1] != 'ready':
                raise Fault(401, 'authorization_failed')
            if self.db.execute('SELECT COUNT(*) FROM sessions').fetchone()[0] >= 10000:
                raise Fault(503, 'busy')
            token = secrets.token_urlsafe(32)
            sid = digest(token)
            tokens = self.open(row[2], key)
            self.db.execute('INSERT INTO sessions VALUES (?,?,?)',
                            (sid, time.time() + 30 * 86400, self.seal(tokens, sid)))
            self.db.execute('DELETE FROM pending WHERE state=?', (key,))
            return dict(session=token, **self.public(tokens))

    @staticmethod
    def public(tokens):
        return dict(access_token=tokens['access_token'],
                    expires_in=max(0, int(tokens['expires_at'] - time.time())))

    def access(self, session):
        sid = digest(credential(session))
        self.limits.take('device:' + sid, 6)
        with self.refresh_locks[int(sid[:4], 16) % 64]:
            with self.lock, self.db:
                self.cleanup()
                row = self.db.execute('SELECT payload FROM sessions WHERE id=?', (sid,)).fetchone()
                if not row:
                    raise Fault(401, 'reauthorize')
                tokens = self.open(row[0], sid)
            if tokens['expires_at'] < time.time() + 120:
                try:
                    tokens = self.tokens(dict(grant_type='refresh_token', refresh_token=tokens['refresh_token']))
                except Fault as error:
                    if error.status == 401:
                        self.revoke(session)
                    raise
                with self.lock, self.db:
                    changed = self.db.execute('UPDATE sessions SET payload=?,expires=? WHERE id=?',
                        (self.seal(tokens, sid), time.time() + 30 * 86400, sid)).rowcount
                    if not changed:
                        raise Fault(401, 'reauthorize')
            return self.public(tokens)

    def revoke(self, session):
        sid = digest(credential(session))
        with self.lock, self.db:
            self.db.execute('DELETE FROM sessions WHERE id=?', (sid,))
        return dict(ok=True)


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 16

    def __init__(self, address, broker, origin_secret):
        self.broker, self.origin_secret = broker, origin_secret
        self.slots = threading.BoundedSemaphore(16)
        super().__init__(address, Handler)

    def process_request(self, request, address):
        request.settimeout(15)
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()

    def handle_error(self, request, address):
        pass  # No request data in traceback logs.


class Handler(BaseHTTPRequestHandler):
    server_version = 'ModuAuth'

    def log_message(self, *args):
        pass

    def reply(self, status, value, html=False):
        body = value.encode() if html else json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'text/html; charset=utf-8' if html else 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'")
        if status in (429, 503):
            self.send_header('Retry-After', '60')
        self.end_headers()
        self.wfile.write(body)

    def dispatch(self):
        try:
            supplied = self.headers.get('X-Modu-Origin', '')
            if not hmac.compare_digest(supplied.encode(), self.server.origin_secret.encode()):
                raise Fault(403, 'forbidden')
            broker = self.server.broker
            broker.limits.take('global', 300)
            # Nginx overwrites this only after verifying the authenticated CF hop.
            ip = self.headers.get('X-Modu-Client-IP', self.client_address[0])[:64]
            broker.limits.take('ip:' + ip, 60)
            url = urllib.parse.urlsplit(self.path)
            if self.command == 'GET' and url.path == broker.callback_path:
                q = urllib.parse.parse_qs(url.query, max_num_fields=10)
                if any(len(v) != 1 for v in q.values()):
                    raise Fault(400, 'invalid_callback')
                broker.callback(q.get('state', [''])[0], q.get('code', [''])[0], 'error' in q)
                self.reply(200, '<!doctype html><meta charset="utf-8"><title>默读</title>'
                               '<h1>百度网盘授权完成</h1><p>请返回默读，继续浏览书籍。</p>', True)
                return
            if self.command != 'POST' or url.query:
                raise Fault(404, 'not_found')
            if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length', [])) != 1:
                raise Fault(400, 'invalid_body')
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 4096:
                raise Fault(413, 'body_too_large')
            if self.headers.get('Content-Type', '').split(';')[0] != 'application/json':
                raise Fault(415, 'json_required')
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise Fault(400, 'invalid_body')
            authorization = self.headers.get('Authorization', '')
            session = authorization[7:] if authorization.startswith('Bearer ') else ''
            if url.path == '/v1/start':
                result = broker.start(data.get('challenge'), ip)
            elif url.path == '/v1/claim':
                result = broker.claim(data.get('ticket'), data.get('proof'))
            elif url.path == '/v1/token':
                result = broker.access(session)
            elif url.path == '/v1/revoke':
                result = broker.revoke(session)
            else:
                raise Fault(404, 'not_found')
            self.reply(200, result)
        except Fault as error:
            self.reply(error.status, dict(error=error.code))
        except (ValueError, TypeError):
            self.reply(400, dict(error='invalid_request'))
        except Exception:
            self.reply(503, dict(error='unavailable'))

    do_POST = dispatch
    do_GET = dispatch


if __name__ == '__main__':
    os.umask(0o077)
    with open(os.environ['MODU_AUTH_CONFIG']) as file:
        config = json.load(file)
    if not all(isinstance(config.get(k), str) and config[k].strip()
               for k in ('app_key', 'app_secret', 'encryption_key', 'origin_secret')):
        raise SystemExit('Incomplete auth configuration')
    key = bytes.fromhex(config['encryption_key'])
    credential(config['origin_secret'])
    service = Broker('/var/lib/modu-baidu-auth/auth.sqlite', key,
                     config['app_key'], config['app_secret'], 'https://baidu-auth.2406.fun')
    Server(('127.0.0.1', 18081), service, config['origin_secret']).serve_forever()
