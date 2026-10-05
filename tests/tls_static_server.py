"""Test-only: serve a directory over HTTPS, standing in for itch.io's game host."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import ssl
import sys

directory, cert, key, port = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
server = ThreadingHTTPServer(('127.0.0.1', port), partial(Quiet, directory=directory))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(cert, key)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
