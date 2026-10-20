"""Serve the built Flutter app locally with clean-URL fallback."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import argparse

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        route = urlsplit(self.path).path
        candidate = Path(self.directory) / route.lstrip('/')
        if not candidate.exists() and not Path(route).suffix:
            self.path = '/index.html'
        super().do_GET()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1] / 'build' / 'web'
    if not (root / 'index.html').exists():
        raise SystemExit('Run flutter build web --debug --no-web-resources-cdn first.')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), lambda *a, **kw: Handler(*a, directory=str(root), **kw))
    print(f'Booking OS: http://localhost:{args.port}', flush=True)
    server.serve_forever()
