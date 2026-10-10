# Stand-in for n8n C04, for testing OrtheaLaunch.ps1. Records each request to requests.jsonl.
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
LOG = sys.argv[2]
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode('utf-8')
        key = self.headers.get('X-Orthea-Key', '')
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'key': key, 'ctype': self.headers.get('Content-Type'), 'body': json.loads(body)}, ensure_ascii=False) + '\n')
        mode = json.loads(body).get('dolphinId', '')
        if key != 'olk_good':           code, out = 403, {'error': 'key not recognised'}
        elif mode == 'ERR500':          code, out = 500, {'message': 'boom'}
        elif mode == 'EVIL':            code, out = 200, {'url': 'https://evil.example/#/launch/x', 'outcome': 'guid'}
        elif mode == 'TEXT':            code, out = 200, None
        else:                           code, out = 200, {'url': 'https://orthea-budibase.eqawdd.easypanel.host/app/default%20workspace/consult#/launch/abc123', 'outcome': 'guid'}
        self.send_response(code)
        if out is None:
            data = json.dumps({'url': 'https://orthea-budibase.eqawdd.easypanel.host/app/x/consult#/launch/t1', 'outcome': 'created'}).encode()
            self.send_header('Content-Type', 'text/plain')
        else:
            data = json.dumps(out).encode(); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
