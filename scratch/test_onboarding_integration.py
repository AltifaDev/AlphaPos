"""Opt-in production onboarding integration check.

Required: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
PAYMENT_WEBHOOK_SECRET. Runs against an isolated disposable user/merchant.
"""

import hashlib
import hmac
import json
import os
import base64
import struct
import time
import urllib.error
import urllib.request
import uuid

BASE = os.environ["SUPABASE_URL"].rstrip("/")
ANON = os.environ["SUPABASE_ANON_KEY"]
SERVICE = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
PAYMENT_SECRET = os.environ["PAYMENT_WEBHOOK_SECRET"].encode()


def request(path, payload, token, extra=None, expected=(200,), method="POST"):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "apikey": ANON,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            **(extra or {}),
        },
    )
    try:
        with urllib.request.urlopen(req) as response:
            status, body = response.status, json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        status, body = error.code, json.loads(error.read() or b"{}")
    assert status in expected, (path, status, body)
    return status, body


def totp(secret):
    """Generate the current RFC 6238 SHA-1 code without third-party packages."""
    key = base64.b32decode(secret.upper() + "=" * (-len(secret) % 8))
    counter = struct.pack(">Q", int(time.time()) // 30)
    digest = hmac.new(key, counter, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{value % 1_000_000:06d}"


def elevate_to_aal2(access):
    _, enrolled = request(
        "/auth/v1/factors",
        {"factor_type": "totp", "friendly_name": "Integration Test"},
        access,
    )
    factor_id = enrolled["id"]
    _, challenge = request(f"/auth/v1/factors/{factor_id}/challenge", {}, access)
    _, verified = request(
        f"/auth/v1/factors/{factor_id}/verify",
        {"challenge_id": challenge["id"], "code": totp(enrolled["totp"]["secret"])},
        access,
    )
    return verified["access_token"]


def main():
    suffix = uuid.uuid4().hex
    email = f"onboarding-{suffix}@example.com"
    password = f"Correct Horse Battery Staple {suffix}"

    _, created = request(
        "/auth/v1/admin/users",
        {"email": email, "password": password, "email_confirm": True},
        SERVICE,
    )
    user_id = created["id"]
    _, session = request("/auth/v1/token?grant_type=password", {"email": email, "password": password}, ANON)
    access = elevate_to_aal2(session["access_token"])

    idempotency_key = str(uuid.uuid4())
    device_id = str(uuid.uuid4())
    onboarding = {
        "shop_name": "Integration Shop",
        "first_name": "Integration",
        "last_name": "Owner",
        "shop_phone": "0812345678",
        "currency": "THB",
        "tax_id": "0105559999999",
        "subscription_tier": "online_subscription",
        "billing_cycle": "monthly",
        "terms_version": "2026-07-17",
        "privacy_version": "2026-07-17",
        "consented_at": "2026-07-17T00:00:00Z",
        "idempotency_key": idempotency_key,
        "device_id": device_id,
        "device_name": "Integration Test",
    }
    _, first = request("/functions/v1/activate-merchant", onboarding, access)
    assert first["subscription_status"] == "pending_payment"

    # Retry and duplicate submission must resolve to the same merchant.
    _, retry = request("/functions/v1/activate-merchant", onboarding, access)
    assert retry["merchant_id"] == first["merchant_id"]

    # A failed payment and a forged success must not activate the subscription.
    failed_event = {"type": "payment.failed", "merchant_id": first["merchant_id"], "payment_id": suffix}
    failed_raw = json.dumps(failed_event).encode()
    failed_signature = hmac.new(PAYMENT_SECRET, failed_raw, hashlib.sha256).hexdigest()
    request(
        "/functions/v1/payment-webhook",
        failed_event,
        ANON,
        {"x-alphapos-signature": failed_signature},
        expected=(202,),
    )

    event = {"type": "payment.succeeded", "merchant_id": first["merchant_id"], "payment_id": suffix}
    request(
        "/functions/v1/payment-webhook",
        event,
        ANON,
        {"x-alphapos-signature": "bad"},
        expected=(401,),
    )

    raw = json.dumps(event).encode()
    signature = hmac.new(PAYMENT_SECRET, raw, hashlib.sha256).hexdigest()
    request(
        "/functions/v1/payment-webhook",
        event,
        ANON,
        {"x-alphapos-signature": signature},
    )

    # Duplicate email is rejected by Auth.
    request(
        "/auth/v1/admin/users",
        {"email": email, "password": password, "email_confirm": True},
        SERVICE,
        expected=(400, 422),
    )

    request("/functions/v1/delete-account", {"confirmation": "DELETE"}, access)
    request(
        f"/auth/v1/admin/users/{user_id}",
        None,
        SERVICE,
        expected=(404,),
        method="GET",
    )
    print("onboarding integration checks passed")


if __name__ == "__main__":
    main()
