"""app1 backend API: reports which pod answered, whether the database is reachable, and when."""

import os
import socket
from datetime import datetime, timezone
from pathlib import Path

import psycopg
from flask import Flask, jsonify

app = Flask(__name__)

# The db-credentials Secret (synced from Secrets Manager by External Secrets) is mounted here.
SECRET_DIR = Path(os.environ.get("DB_SECRET_DIR", "/etc/db"))


def db_connect():
    # Credentials are read on every connect: RDS rotates the password and the mounted Secret follows.
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=(SECRET_DIR / "username").read_text().strip(),
        password=(SECRET_DIR / "password").read_text().strip(),
        sslmode="require",
        connect_timeout=3,
    )


def db_connected():
    try:
        with db_connect() as conn:
            conn.execute("SELECT 1")
        return True
    except Exception:
        app.logger.exception("database check failed")
        return False


@app.get("/")
def index():
    connected = db_connected()
    body = {
        "pod_name": os.environ.get("POD_NAME", socket.gethostname()),
        "db_status": "connected" if connected else "disconnected",
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    return jsonify(body), 200 if connected else 503


# Liveness/readiness and ALB health check. Does not touch the database, so a database outage
# doesn't restart every pod.
@app.get("/healthz")
def healthz():
    return jsonify(status="ok")
