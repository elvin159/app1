"""app1 frontend: GET / runs SELECT 1 on RDS and returns the result as JSON."""

import os
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


def select_one():
    with db_connect() as conn:
        return conn.execute("SELECT 1").fetchone()[0]


@app.get("/")
def index():
    try:
        result = select_one()
    except Exception:
        app.logger.exception("SELECT 1 failed")
        return jsonify(query="SELECT 1", result=None, db_status="disconnected"), 503
    return jsonify(query="SELECT 1", result=result, db_status="connected")


# Liveness/readiness and ALB health check. Does not touch the database.
@app.get("/healthz")
def healthz():
    return jsonify(status="ok")
