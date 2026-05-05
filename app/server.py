"""Minimal Hello World HTTP server for the FinCore IDP walking-stick demo.

Stays deliberately small (no framework, no dependencies) so the demo's
attention stays on the platform — pipeline, IaC, observability — not on the
service itself. Any product team can swap this for their real workload by
keeping the same shape: bind 0.0.0.0:$PORT, return 200 on `/`, log to stdout.

Cloud Run injects the PORT env var (defaulting to 8080); we honour it.
"""
import logging
import os
import signal
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = logging.getLogger("hello")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
    stream=sys.stdout,
)

# ─── Response payloads ──────────────────────────────────────────────────────
# Edit these two strings to change what the service returns. They're the only
# knobs a product-team developer needs to touch when adapting this sample.
# Override at runtime via env vars (HELLO_MESSAGE / HEALTH_MESSAGE) without
# rebuilding the image — handy for canary tests in the demo.
HELLO_MESSAGE: str = os.environ.get("HELLO_MESSAGE", "Hello World !")
HEALTH_MESSAGE: str = os.environ.get("HEALTH_MESSAGE", "ok")


class HelloHandler(BaseHTTPRequestHandler):
    """Returns `HELLO_MESSAGE` on every GET; `HEALTH_MESSAGE` on /healthz."""

    def do_GET(self) -> None:  # noqa: N802 — stdlib API
        if self.path == "/healthz":
            body = f"{HEALTH_MESSAGE}\n".encode("utf-8")
            self._respond(200, "text/plain; charset=utf-8", body)
            return
        body = f"{HELLO_MESSAGE}\n".encode("utf-8")
        self._respond(200, "text/plain; charset=utf-8", body)

    def _respond(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:
        # Route stdlib's per-request log through our structured logger so Cloud
        # Logging picks it up with severity INFO instead of stderr noise.
        LOG.info("%s - %s", self.address_string(), fmt % args)


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer(("0.0.0.0", port), HelloHandler)

    # Graceful shutdown — Cloud Run sends SIGTERM during scale-in / revision swap.
    def _shutdown(*_: object) -> None:
        LOG.info("Received shutdown signal, stopping server")
        server.shutdown()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    LOG.info("Listening on 0.0.0.0:%d", port)
    server.serve_forever()


if __name__ == "__main__":
    main()
