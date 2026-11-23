from flask import Flask
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy
from prometheus_flask_exporter import PrometheusMetrics

from app.config import Config
from app.logging_config import configure_logging

configure_logging()

app = Flask(__name__)
app.config.from_object(Config)
db = SQLAlchemy(app)
migrate = Migrate(app, db)

# Exposes /metrics in Prometheus format. Probe and scrape requests are left out of the
# request metrics, so they only count real traffic.
metrics = PrometheusMetrics(app, group_by="endpoint", excluded_paths=["^/metrics$", "^/health$", "^/ready$"])
metrics.info("app_info", "Application version", version=Config.APP_VERSION)

from app import models, routes  # noqa: E402, F401  (routes register themselves on import)
