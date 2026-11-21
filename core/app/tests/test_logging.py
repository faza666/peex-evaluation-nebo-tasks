import json
import logging
import sys
import unittest

from app.logging_config import JsonFormatter


def make_record(name, msg, args=(), exc_info=None):
    return logging.LogRecord(name, logging.INFO, __file__, 1, msg, args, exc_info)


class JsonFormatterTests(unittest.TestCase):
    def setUp(self):
        self.formatter = JsonFormatter()

    def test_plain_message(self):
        entry = json.loads(self.formatter.format(make_record("app.routes", "hello %s", ("world",))))
        self.assertEqual(entry["message"], "hello world")
        self.assertEqual(entry["level"], "INFO")
        self.assertEqual(entry["logger"], "app.routes")
        self.assertTrue(entry["time"].endswith("+00:00"))

    def test_gunicorn_access_record_becomes_fields(self):
        atoms = {"h": "10.0.0.1", "m": "GET", "U": "/menu", "q": "", "s": "200", "B": 42, "M": 3, "a": "curl/8"}
        entry = json.loads(self.formatter.format(make_record("gunicorn.access", "%(h)s", (atoms,))))
        self.assertEqual(entry["message"], "request")
        self.assertEqual(entry["method"], "GET")
        self.assertEqual(entry["path"], "/menu")
        self.assertEqual(entry["status"], 200)
        self.assertEqual(entry["bytes"], 42)
        self.assertEqual(entry["duration_ms"], 3)
        self.assertNotIn("query", entry)

    def test_exception_is_included(self):
        try:
            raise ZeroDivisionError("boom")
        except ZeroDivisionError:
            record = make_record("app", "failed", exc_info=sys.exc_info())
        entry = json.loads(self.formatter.format(record))
        self.assertIn("ZeroDivisionError", entry["exception"])


if __name__ == "__main__":
    unittest.main()
