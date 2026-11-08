import concurrent.futures
import http.client
import json
import secrets
import threading
import time
import unittest
from broker import Broker, Fault, Limits, Server, digest


class BrokerTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def exchange(fields):
            self.calls.append(fields)
            return dict(access_token='access-secret', refresh_token='refresh-secret', expires_in=3600)
        self.broker = Broker(':memory:', secrets.token_bytes(32), 'app', 'secret',
                             'https://baidu-auth.2406.fun', exchange)
        self.proof = secrets.token_urlsafe(32)
        self.ticket = self.broker.start(digest(self.proof), 'test')['ticket']

    def tearDown(self):
        self.broker.db.close()

    def session(self):
        self.broker.callback(self.ticket, 'code')
        return self.broker.claim(self.ticket, self.proof)['session']

    def test_proof_one_time_and_encrypted_storage(self):
        self.assertEqual(self.broker.claim(self.ticket, self.proof), {'pending': True})
        with self.assertRaises(Fault):
            self.broker.claim(self.ticket, secrets.token_urlsafe(32))
        session = self.session()
        with self.assertRaises(Fault):
            self.broker.claim(self.ticket, self.proof)
        with self.assertRaises(Fault):
            self.broker.callback(self.ticket, 'replay')
        row = self.broker.db.execute('SELECT id,payload FROM sessions').fetchone()
        self.assertNotEqual(row[0], session)
        self.assertNotIn(b'access-secret', row[1])
        self.assertNotIn(b'refresh-secret', row[1])
        self.assertNotIn('refresh_token', self.broker.access(session))
        self.broker.revoke(session)
        with self.assertRaises(Fault):
            self.broker.access(session)

    def test_expiry_and_denied(self):
        with self.assertRaises(Fault):
            self.broker.callback(self.ticket, None, denied=True)
        with self.assertRaises(Fault):
            self.broker.claim(self.ticket, self.proof)
        self.assertEqual(self.calls, [])
        self.broker.db.execute('UPDATE pending SET expires=0')
        with self.assertRaises(Fault):
            self.broker.callback(self.ticket, 'code')

    def test_refresh_is_single_flight(self):
        session = self.session()
        sid = digest(session)
        payload = self.broker.seal(dict(access_token='old', refresh_token='refresh-secret', expires_at=0), sid)
        with self.broker.db:
            self.broker.db.execute('UPDATE sessions SET payload=?', (payload,))
        with concurrent.futures.ThreadPoolExecutor(4) as pool:
            results = list(pool.map(lambda _: self.broker.access(session), range(4)))
        self.assertEqual(len(self.calls), 2)
        self.assertTrue(all(x['access_token'] == 'access-secret' for x in results))
        self.assertEqual(self.calls[-1]['grant_type'], 'refresh_token')

    def test_revocation_during_refresh_cannot_restore_session(self):
        session = self.session()
        sid = digest(session)
        with self.broker.db:
            self.broker.db.execute('UPDATE sessions SET payload=?',
              (self.broker.seal(dict(access_token='old', refresh_token='refresh-secret', expires_at=0), sid),))
        original = self.broker.exchange
        def revoke_while_refreshing(fields):
            self.broker.revoke(session)
            return original(fields)
        self.broker.exchange = revoke_while_refreshing
        with self.assertRaises(Fault):
            self.broker.access(session)
        self.assertEqual(self.broker.db.execute('SELECT COUNT(*) FROM sessions').fetchone()[0], 0)

    def test_malformed_upstream_and_limits(self):
        self.broker.exchange = lambda _: []
        with self.assertRaises(Fault) as result:
            self.broker.callback(self.ticket, 'code')
        self.assertEqual(result.exception.status, 502)
        now = [0]
        limits = Limits(lambda: now[0])
        limits.take('global', 1)
        with self.assertRaises(Fault):
            limits.take('global', 1)
        now[0] = 61
        limits.take('global', 1)

    def test_http_origin_proof_and_bounded_body(self):
        server = Server(('127.0.0.1', 0), self.broker, 'origin-secret')
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            def request(headers, body=b'{}', path='/v1/token'):
                conn = http.client.HTTPConnection(*server.server_address, timeout=3)
                conn.request('POST', path, body, headers)
                response = conn.getresponse()
                result = (response.status, json.loads(response.read()))
                conn.close()
                return result
            self.assertEqual(request({})[0], 403)
            headers = {'X-Modu-Origin': 'origin-secret', 'Content-Type': 'application/json'}
            self.assertEqual(request(headers, b'x' * 4097)[0], 413)
            self.assertEqual(request(headers, b'[]')[0], 400)
            session = self.session()
            self.assertEqual(request(dict(headers, Authorization=session))[0], 400)
            self.assertEqual(request(dict(headers, Authorization='Bearer ' + session))[0], 200)
            self.assertEqual(request(headers, path='/file/download')[0], 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

if __name__ == '__main__':
    unittest.main()
