"""Temporarily serve only the generated, credential-free Edge source on loopback."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from html import escape
import secrets
root=Path(__file__).resolve().parents[1]
path='/'+secrets.token_urlsafe(24)
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path!=path:self.send_error(404);return
        source=(root/'supabase/functions/booking-api/index.ts').read_text()
        body=('<!doctype html><title>Booking API deployment source</title><h1>Booking API deployment source</h1><p>Generated code only. No credentials.</p><label>Deployment source<textarea aria-label="Deployment source" style="width:95vw;height:70vh">'+escape(source)+'</textarea></label>').encode()
        self.send_response(200)
        self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.send_header('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'")
        self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
server=HTTPServer(('127.0.0.1',0),Handler)
print(f'http://127.0.0.1:{server.server_port}{path}',flush=True)
server.serve_forever()
