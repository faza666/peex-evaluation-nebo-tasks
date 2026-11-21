"""JSON logging to stdout for the app and for gunicorn, using only the standard library."""

import json
import logging
import os
import sys
from datetime import datetime, timezone

# Gunicorn passes its access-log atoms as the record's args; these become JSON fields.
ACCESS_FIELDS = {
    "h": "remote_addr",
    "m": "method",
    "U": "path",
    "q": "query",
    "s": "status",
    "B": "bytes",
    "M": "duration_ms",
    "a": "user_agent",
}
NUMERIC_FIELDS = {"status", "bytes", "duration_ms"}


def _number_or_text(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return value


class JsonFormatter(logging.Formatter):
    """One JSON object per line: time, level, logger, message, plus request fields for access logs."""

    def format(self, record):
        entry = {
            "time": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(timespec="milliseconds"),
            "level": record.levelname,
            "logger": record.name,
        }
        if record.name == "gunicorn.access" and isinstance(record.args, dict):
            entry["message"] = "request"
            for atom, key in ACCESS_FIELDS.items():
                value = record.args.get(atom)
                if value in (None, "", "-"):
                    continue
                entry[key] = _number_or_text(value) if key in NUMERIC_FIELDS else value
        else:
            entry["message"] = record.getMessage()
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, ensure_ascii=False)


def configure_logging(level=None):
    """Send all logs to stdout as JSON. Safe to call more than once."""
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(level or os.environ.get("LOG_LEVEL", "INFO"))
