import urllib.request
import json

ef_url = "https://your-supabase-project.supabase.co/functions/v1/issue-merchant-token"
rest_url = "https://your-supabase-project.supabase.co/rest/v1/restaurant_tables"
anon_key = "your-anon-key"

auth_payload = {
    "merchant_id": "your-merchant-uuid",
    "device_secret": "your-device-secret"
}

# 1. Fetch token
req_auth = urllib.request.Request(
    ef_url,
    data=json.dumps(auth_payload).encode('utf-8'),
    headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {anon_key}"
    },
    method="POST"
)

try:
    with urllib.request.urlopen(req_auth) as response:
        res_data = json.loads(response.read().decode('utf-8'))
        print("Auth response:", json.dumps(res_data, indent=2))
        jwt_token = res_data.get("access_token")
except Exception as e:
    print("Failed to authenticate:", e)
    jwt_token = None

if jwt_token:
    # 2. Query tables with JWT
    req_query = urllib.request.Request(
        rest_url,
        headers={
            "apikey": anon_key,
            "Authorization": f"Bearer {jwt_token}"
        },
        method="GET"
    )
    try:
        with urllib.request.urlopen(req_query) as response:
            tables = json.loads(response.read().decode('utf-8'))
            print(f"Tables retrieved: {len(tables)}")
            for t in tables:
                print(f"Table {t.get('table_number')} (Floor {t.get('floor')}): posX={t.get('position_x')}, posY={t.get('position_y')}, status={t.get('status')}")
    except urllib.error.HTTPError as e:
        print("Failed to fetch tables with JWT (HTTP Error):", e.code)
        print("Response body:", e.read().decode('utf-8'))
    except Exception as e:
        print("Failed to fetch tables with JWT:", e)
