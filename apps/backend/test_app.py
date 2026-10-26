import re

import pytest

import app as backend


@pytest.fixture
def client():
    return backend.app.test_client()


def test_index_connected(client, monkeypatch):
    monkeypatch.setattr(backend, "db_connected", lambda: True)
    monkeypatch.setenv("POD_NAME", "backend-api-abc123")

    resp = client.get("/")

    assert resp.status_code == 200
    body = resp.get_json()
    assert body["pod_name"] == "backend-api-abc123"
    assert body["db_status"] == "connected"
    assert re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", body["timestamp"])


def test_index_disconnected(client, monkeypatch):
    monkeypatch.setattr(backend, "db_connected", lambda: False)

    resp = client.get("/")

    assert resp.status_code == 503
    assert resp.get_json()["db_status"] == "disconnected"


def test_pod_name_falls_back_to_hostname(client, monkeypatch):
    monkeypatch.setattr(backend, "db_connected", lambda: True)
    monkeypatch.delenv("POD_NAME", raising=False)
    monkeypatch.setattr(backend.socket, "gethostname", lambda: "host-1")

    assert client.get("/").get_json()["pod_name"] == "host-1"


def test_db_connected_false_on_error(monkeypatch):
    def boom():
        raise OSError("unreachable")

    monkeypatch.setattr(backend, "db_connect", boom)

    assert backend.db_connected() is False


def test_db_connect_reads_mounted_credentials(tmp_path, monkeypatch):
    (tmp_path / "username").write_text("dbadmin\n")
    (tmp_path / "password").write_text("s3cret\n")
    monkeypatch.setattr(backend, "SECRET_DIR", tmp_path)
    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.setenv("DB_NAME", "app1")
    captured = {}
    monkeypatch.setattr(backend.psycopg, "connect", lambda **kw: captured.update(kw))

    backend.db_connect()

    assert captured["user"] == "dbadmin"
    assert captured["password"] == "s3cret"
    assert captured["sslmode"] == "require"


def test_healthz(client):
    resp = client.get("/healthz")

    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}
