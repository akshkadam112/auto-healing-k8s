import os
import sys
import time
import threading
import logging
from flask import Flask, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

app = Flask(__name__)

REQUEST_COUNT = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request latency", ["endpoint"]
)


# ---------------------------------------------------------------------------
# Startup failure injectors
# ---------------------------------------------------------------------------

def _maybe_crashloop():
    """Exit at startup → CrashLoopBackOff. Healed by kopf crashloop handler."""
    if os.environ.get("CRASH_ON_START", "").lower() in ("1", "true", "yes"):
        log.error("CRASH_ON_START set — crashing to simulate CrashLoopBackOff")
        sys.exit(1)


def _maybe_slow_start():
    """Sleep before Flask binds → readiness probe fails → rollout hangs.
    Healed by kopf stuck-rollout handler after progressDeadlineSeconds."""
    seconds = int(os.environ.get("SLOW_START_SECONDS", "0"))
    if seconds > 0:
        log.warning("SLOW_START_SECONDS=%d — delaying startup to simulate stuck rollout", seconds)
        time.sleep(seconds)


def _maybe_hog_memory():
    """Allocate MEMORY_HOG_MB megabytes → exceeds pod memory limit → OOMKill.
    Healed by kopf oomkill handler (raises memory limit + restarts)."""
    mb = int(os.environ.get("MEMORY_HOG_MB", "0"))
    if mb <= 0:
        return

    def hog():
        log.warning("Allocating %d MB to simulate OOM pressure", mb)
        _blob = bytearray(mb * 1024 * 1024)  # noqa: F841 — intentional reference hold
        while True:
            time.sleep(60)

    threading.Thread(target=hog, daemon=True).start()


def _maybe_stress_cpu():
    """Spin CPU_STRESS_CORES busy threads → node CPU saturation demo.
    Node-level healing is handled by Karpenter eviction thresholds."""
    cores = int(os.environ.get("CPU_STRESS_CORES", "0"))
    for _ in range(cores):
        def spin():
            while True:
                pass
        threading.Thread(target=spin, daemon=True).start()
    if cores:
        log.warning("CPU_STRESS_CORES=%d — spinning busy threads", cores)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/")
def index():
    delay = float(os.environ.get("RESPONSE_DELAY", "0"))
    if delay > 0:
        time.sleep(delay)
    REQUEST_COUNT.labels(method="GET", endpoint="/", status="200").inc()
    return jsonify({"status": "ok", "app": "sample-app"})


@app.route("/health")
def health():
    """Liveness probe target.
    LIVENESS_FAIL=true → returns 500 → kubelet restarts pod (K8s native healing)."""
    if os.environ.get("LIVENESS_FAIL", "").lower() in ("1", "true", "yes"):
        REQUEST_COUNT.labels(method="GET", endpoint="/health", status="500").inc()
        return jsonify({"status": "failing", "reason": "LIVENESS_FAIL set"}), 500
    REQUEST_COUNT.labels(method="GET", endpoint="/health", status="200").inc()
    return jsonify({"status": "healthy"}), 200


@app.route("/ready")
def ready():
    """Readiness probe target.
    READINESS_FAIL=true → returns 503 → pod removed from Service endpoints (K8s native)."""
    if os.environ.get("READINESS_FAIL", "").lower() in ("1", "true", "yes"):
        REQUEST_COUNT.labels(method="GET", endpoint="/ready", status="503").inc()
        return jsonify({"status": "not ready", "reason": "READINESS_FAIL set"}), 503
    REQUEST_COUNT.labels(method="GET", endpoint="/ready", status="200").inc()
    return jsonify({"status": "ready"}), 200


@app.route("/metrics")
def metrics():
    """Prometheus scrape endpoint."""
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    _maybe_crashloop()       # exits here if CRASH_ON_START=true
    _maybe_slow_start()      # blocks here if SLOW_START_SECONDS>0
    _maybe_hog_memory()      # background thread OOM pressure
    _maybe_stress_cpu()      # background threads CPU pressure
    port = int(os.environ.get("PORT", "8080"))
    log.info("Starting sample-app on port %d", port)
    app.run(host="0.0.0.0", port=port)
