import pytest

import app as frontend


@pytest.fixture
def client():
    return frontend.app.test_client()


def test_index_returns_select_one(client, monkeypatch):
    monkeypatch.setattr(frontend, "select_one", lambda: 1)

    resp = client.get("/")

    assert resp.status_code == 200
    assert resp.get_json() == {"query": "SELECT 1", "result": 1, "db_status": "connected"}


def test_index_database_down(client, monkeypatch):
    def boom():
        raise OSError("unreachable")

    monkeypatch.setattr(frontend, "select_one", boom)

    resp = client.get("/")

    assert resp.status_code == 503
    assert resp.get_json() == {"query": "SELECT 1", "result": None, "db_status": "disconnected"}


def test_select_one_runs_query(monkeypatch):
    executed = []

    class Conn:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def execute(self, sql):
            executed.append(sql)
            return self

        def fetchone(self):
            return (1,)

    monkeypatch.setattr(frontend, "db_connect", Conn)

    assert frontend.select_one() == 1
    assert executed == ["SELECT 1"]


def test_db_connect_reads_mounted_credentials(tmp_path, monkeypatch):
    (tmp_path / "username").write_text("dbadmin\n")
    (tmp_path / "password").write_text("s3cret\n")
    monkeypatch.setattr(frontend, "SECRET_DIR", tmp_path)
    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.setenv("DB_NAME", "app1")
    captured = {}
    monkeypatch.setattr(frontend.psycopg, "connect", lambda **kw: captured.update(kw))

    frontend.db_connect()

    assert captured["user"] == "dbadmin"
    assert captured["password"] == "s3cret"
    assert captured["sslmode"] == "require"


def test_healthz(client):
    resp = client.get("/healthz")

    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_static_page_is_environment_agnostic():
    html = (frontend.Path(__file__).parent / "static" / "index.html").read_text()

    # The same build is promoted to every environment, so no environment's domain may be baked in.
    assert "example.com" not in html
    assert 'id="frontend"' in html and 'id="backend"' in html
    assert 'location.hostname.replace(/^static\\./, "")' in html
