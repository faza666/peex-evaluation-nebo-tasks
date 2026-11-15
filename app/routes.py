import logging

from flask import jsonify
from sqlalchemy import text

from app import app, db
from app.models import Menu

log = logging.getLogger(__name__)


@app.route("/")
def home():
    return jsonify({"status": "ok"})


@app.route("/menu")
def menu():
    today = db.session.execute(db.select(Menu)).scalars().first()
    if today:
        return jsonify({"today_special": today.name}), 200
    return jsonify({"error": "Sorry, the service is not available today."}), 404


@app.route("/health")
def health():
    """Liveness: the process is up and serving requests."""
    return jsonify({"status": "ok", "version": app.config["APP_VERSION"]})


@app.route("/ready")
def ready():
    """Readiness: the database answers a trivial query."""
    try:
        db.session.execute(text("SELECT 1"))
    except Exception:  # any database error means the app can't serve requests
        log.warning("readiness check failed: database unavailable", exc_info=True)
        db.session.rollback()
        return jsonify({"status": "unavailable", "database": "error"}), 503
    return jsonify({"status": "ok", "database": "ok"})
