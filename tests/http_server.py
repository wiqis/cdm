#!/usr/bin/env python3
"""ChemicalDM http_tests helper server.

Serves a single fixed file (given as argv[1]) over HTTP/1.1 on 127.0.0.1:argv[2]
with full Range-request support (206 + Content-Range) and Accept-Ranges, exactly
like a real download host. Threaded so the segmented engine can open several
connections at once. Run in the background by the Chemical test harness.
"""
import sys
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main():
    path = sys.argv[1]
    port = int(sys.argv[2])
    with open(path, "rb") as fh:
        data = fh.read()
    size = len(data)

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            rng = self.headers.get("Range")
            if rng:
                spec = rng.split("=")[1]
                parts = spec.split("-")
                start = int(parts[0])
                if len(parts) > 1 and parts[1] != "":
                    end = int(parts[1])
                else:
                    end = size - 1
                if end >= size:
                    end = size - 1
                chunk = data[start:end + 1]
                self.send_response(206)
                self.send_header("Content-Range",
                                 "bytes %d-%d/%d" % (start, end, size))
                self.send_header("Content-Length", str(len(chunk)))
                self.end_headers()
                self.wfile.write(chunk)
            else:
                self.send_response(200)
                self.send_header("Content-Length", str(size))
                self.send_header("Accept-Ranges", "bytes")
                self.end_headers()
                self.wfile.write(data)

        def log_message(self, *args):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
