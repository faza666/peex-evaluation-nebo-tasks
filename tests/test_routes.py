import json
import unittest
from unittest import mock

from sqlalchemy.exc import OperationalError

from app import app, db
from app.models import Menu


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.ctx = app.app_context()
        self.ctx.push()
        db.drop_all()
        db.create_all()
        self.client = app.test_client()

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.ctx.pop()

    def get_json(self, path):
        response = self.client.get(path)
        return response, json.loads(response.data)

    def test_home(self):
        response, body = self.get_json("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "application/json")
        self.assertEqual(body["status"], "ok")

    def test_menu_empty(self):
        response = self.client.get("/menu")
        self.assertEqual(response.status_code, 404)

    def test_menu_item(self):
        db.session.add(Menu(name="test"))
        db.session.commit()
        response, body = self.get_json("/menu")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "application/json")
        self.assertEqual(body["today_special"], "test")

    def test_health(self):
        response, body = self.get_json("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(body, {"status": "ok", "version": app.config["APP_VERSION"]})

    def test_ready(self):
        response, body = self.get_json("/ready")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(body["database"], "ok")

    def test_ready_when_database_is_down(self):
        failure = OperationalError("SELECT 1", {}, Exception("connection refused"))
        with mock.patch.object(db.session, "execute", side_effect=failure):
            with self.assertLogs("app.routes", level="WARNING"):
                response, body = self.get_json("/ready")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(body, {"status": "unavailable", "database": "error"})

    def test_metrics(self):
        self.client.get("/menu")
        response = self.client.get("/metrics")
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.content_type.startswith("text/plain"))
        self.assertIn(b"flask_http_request_total", response.data)
        self.assertIn(b'endpoint="menu"', response.data)
        self.assertIn(b"app_info{", response.data)

    def test_probes_are_not_counted_as_requests(self):
        self.client.get("/health")
        self.client.get("/ready")
        data = self.client.get("/metrics").data
        self.assertNotIn(b'endpoint="health"', data)
        self.assertNotIn(b'endpoint="ready"', data)


if __name__ == "__main__":
    unittest.main()
