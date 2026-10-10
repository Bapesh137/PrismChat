"""Local fixture server for tst_avatar_loading.qml; uses no Matrix account."""
import struct
import zlib
from pathlib import Path
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


PNG = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress((b"\0" + b"\x20\xaa\x60\xff" * 2) * 2)) + chunk(b"IEND", b""))
requests = Counter()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        query = parse_qs(urlsplit(self.path).query)
        mxc = query.get("url", [""])[0]
        requests[mxc] += 1
        if "unavailable" in mxc or ("transient" in mxc and requests[mxc] == 1):
            self.send_error(502)
        elif "original-only" in mxc and "width" in query:
            self.send_error(404)
        else:
            webp = "webp" in mxc
            data = (Path(__file__).parent / "data/avatar.webp").read_bytes() if webp else PNG
            self.send_response(200)
            self.send_header("Content-Type", "image/webp" if webp else "image/png")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 18043), Handler).serve_forever()
