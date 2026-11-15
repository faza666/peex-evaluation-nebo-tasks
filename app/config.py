import os

basedir = os.path.abspath(os.path.dirname(__file__))


class Config:
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL") or "sqlite:///" + os.path.join(basedir, "app.db")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    # Set at build time (Docker build arg) or deploy time; shown by /health and the app_info metric.
    APP_VERSION = os.environ.get("APP_VERSION", "dev")
