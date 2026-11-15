"""Gunicorn settings: one worker and JSON logs on stdout."""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8000')}"

# One worker keeps prometheus-flask-exporter on its simple per-process registry.
# Scale out with more replicas, not more workers.
workers = 1
timeout = 30

# The JSON formatter lives in the app package, so loading the log config already imports
# the app in the master process; preloading makes that explicit.
preload_app = True

# Access and error logs both go through app.logging_config.JsonFormatter.
logconfig_dict = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"json": {"()": "app.logging_config.JsonFormatter"}},
    "handlers": {
        "stdout": {"class": "logging.StreamHandler", "stream": "ext://sys.stdout", "formatter": "json"},
    },
    "root": {"level": os.environ.get("LOG_LEVEL", "INFO"), "handlers": ["stdout"]},
    "loggers": {
        "gunicorn.error": {"level": "INFO", "handlers": ["stdout"], "propagate": False},
        "gunicorn.access": {"level": "INFO", "handlers": ["stdout"], "propagate": False},
    },
}
