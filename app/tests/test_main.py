"""Unit tests for the demo application."""
import pytest

from demo_app.main import create_app


@pytest.fixture(name="client")
def client_fixture(monkeypatch):
    """Client with secrets injected, like in a real deployment."""
    monkeypatch.setenv("SECRET_KEY", "unit-test-secret")
    monkeypatch.setenv("API_TOKEN", "unit-test-token")
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    return create_app().test_client()


def test_index(client):
    """The landing page answers with the current environment."""
    response = client.get("/")
    assert response.status_code == 200
    assert response.get_json()["environment"] == "test"


def test_health_with_secrets(client):
    """Health reports that secrets were loaded."""
    body = client.get("/health").get_json()
    assert body["status"] == "ok"
    assert body["secrets_loaded"] is True


def test_health_without_secrets(monkeypatch):
    """Health reports missing secrets without ever exposing them."""
    monkeypatch.delenv("SECRET_KEY", raising=False)
    monkeypatch.delenv("API_TOKEN", raising=False)
    body = create_app().test_client().get("/health").get_json()
    assert body["secrets_loaded"] is False


def test_version(client):
    """The version endpoint exposes the build version."""
    assert client.get("/version").get_json()["version"] == "1.2.3"


def test_unknown_route(client):
    """Unknown routes return 404."""
    assert client.get("/does-not-exist").status_code == 404
