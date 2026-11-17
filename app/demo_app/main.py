"""Minimal Flask service exposing health and version endpoints."""
import os
import time

from flask import Flask, jsonify

START_TIME = time.time()


def create_app() -> Flask:
    """Build the Flask application (secrets are read from the environment)."""
    flask_app = Flask(__name__)
    flask_app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "")
    flask_app.config["API_TOKEN"] = os.environ.get("API_TOKEN", "")
    environment = os.environ.get("APP_ENV", "dev")
    version = os.environ.get("APP_VERSION", "dev")

    @flask_app.get("/")
    def index():
        """Landing endpoint."""
        return jsonify(
            app="demo-app",
            environment=environment,
            message="Hello from the TP02 CI/CD factory",
        )

    @flask_app.get("/health")
    def health():
        """Liveness endpoint; reports whether the secrets were injected."""
        secrets_loaded = bool(flask_app.config["SECRET_KEY"] and flask_app.config["API_TOKEN"])
        return jsonify(
            status="ok",
            secrets_loaded=secrets_loaded,
            uptime_seconds=round(time.time() - START_TIME, 1),
        )

    @flask_app.get("/version")
    def version_info():
        """Return the build version injected at image build time."""
        return jsonify(version=version, environment=environment)

    return flask_app


application = create_app()
