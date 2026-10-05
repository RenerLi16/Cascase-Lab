"""Test-only: run the backend in public mode behind TLS, standing in for Render's HTTPS proxy.

Usage (synthetic rehearsal only): python3 tests/online_rehearsal_server.py CERT KEY PORT
Configuration comes from the same CASCADE_* environment variables used on Render.
"""
from http.server import ThreadingHTTPServer
import ssl
import sys
from backend.config import Config
from backend.server import Service, handler

cert, key, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
config = Config.from_env()
service = Service(config)
server = ThreadingHTTPServer(('127.0.0.1', port), handler(service))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
print(f'rehearsal backend https://cascade.test:{port} public={config.public()} storage={service.store.describe()}', flush=True)
server.serve_forever()
