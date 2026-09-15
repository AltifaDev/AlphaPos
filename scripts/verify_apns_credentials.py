#!/usr/bin/env python3
import argparse
import base64
import json
import subprocess
import time
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


parser = argparse.ArgumentParser(description="Verify APNs provider credentials without notifying a user")
parser.add_argument("--key", required=True)
parser.add_argument("--key-id", required=True)
parser.add_argument("--team-id", required=True)
parser.add_argument("--topic", required=True)
args = parser.parse_args()

private_key = serialization.load_pem_private_key(Path(args.key).read_bytes(), password=None)
header = b64url(json.dumps({"alg": "ES256", "kid": args.key_id}, separators=(",", ":")).encode())
claims = b64url(json.dumps({"iss": args.team_id, "iat": int(time.time())}, separators=(",", ":")).encode())
signing_input = f"{header}.{claims}".encode()
der_signature = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
r_value, s_value = decode_dss_signature(der_signature)
raw_signature = r_value.to_bytes(32, "big") + s_value.to_bytes(32, "big")
jwt = f"{signing_input.decode()}.{b64url(raw_signature)}"

result = subprocess.run(
    [
        "/usr/bin/curl", "--http2", "--silent", "--show-error",
        "--output", "/tmp/alphapos-apns-verification-response.json",
        "--write-out", "%{http_code}", "--request", "POST",
        "--header", f"authorization: bearer {jwt}",
        "--header", f"apns-topic: {args.topic}",
        "--header", "apns-push-type: alert",
        "--data", '{"aps":{"alert":"credential verification"}}',
        f"https://api.push.apple.com/3/device/{'0' * 64}",
    ],
    check=True,
    capture_output=True,
    text=True,
)
response_path = Path("/tmp/alphapos-apns-verification-response.json")
body = json.loads(response_path.read_text() or "{}")
response_path.unlink(missing_ok=True)
if result.stdout == "403" or body.get("reason") == "InvalidProviderToken":
    raise SystemExit(f"APNs rejected provider credentials: {body.get('reason', 'HTTP 403')}")
if body.get("reason") not in {"BadDeviceToken", "DeviceTokenNotForTopic"}:
    raise SystemExit(f"Unexpected APNs response HTTP {result.stdout}: {body.get('reason', 'unknown')}")
print(f"APNs provider authentication passed (HTTP {result.stdout} {body['reason']}, key {args.key_id})")
