import os
import unittest

os.environ["API_AUTH_TOKEN"] = "test-admin-token"
os.environ["ALPHAPOS_ENV"] = "production"

from fastapi.testclient import TestClient

from server_fastapi import app
from api.deps import API_AUTH_TOKEN


class SecurityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def test_private_session_listing_requires_admin_token(self):
        response = self.client.get("/v1/sessions")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers["content-type"], "application/problem+json")
        self.assertEqual(response.json()["code"], "ADMIN_AUTH_REQUIRED")
        self.assertTrue(response.json()["traceId"])

    def test_legacy_order_write_is_retired(self):
        self.assertTrue(API_AUTH_TOKEN, "API_AUTH_TOKEN must be set for this contract test")
        response = self.client.post(
            "/v1/orders",
            headers={"Authorization": f"Bearer {API_AUTH_TOKEN}"},
            json={"id": "unused"},
        )
        self.assertEqual(response.status_code, 410)
        self.assertEqual(response.json()["detail"]["code"], "LEGACY_ORDER_WRITE_RETIRED")

    def test_legacy_payment_write_is_retired(self):
        response = self.client.post(
            "/v1/payments",
            headers={"Authorization": f"Bearer {API_AUTH_TOKEN}"},
            json={"id": "unused"},
        )
        self.assertEqual(response.status_code, 410)
        self.assertEqual(response.json()["detail"]["code"], "LEGACY_PAYMENT_WRITE_RETIRED")

    def test_public_health_does_not_require_admin_token(self):
        response = self.client.get("/v1/sync/supabase-health")
        self.assertNotEqual(response.status_code, 401)
        self.assertTrue(response.headers.get("x-request-id"))


if __name__ == "__main__":
    unittest.main()
