import urllib.request
import json

rest_url = "https://your-supabase-project.supabase.co/rest/v1/restaurant_tables"
anon_key = "your-anon-key"
service_role = "your-service-role-key"

req_query = urllib.request.Request(
    rest_url,
    headers={
        "apikey": service_role,
        "Authorization": f"Bearer {service_role}"
    },
    method="GET"
)

try:
    with urllib.request.urlopen(req_query) as response:
        tables = json.loads(response.read().decode('utf-8'))
        print(f"Tables retrieved with service_role: {len(tables)}")
        for t in tables:
            print(f"ID: {t.get('id')} - Merchant: {t.get('merchant_id')} - Table {t.get('table_number')} (Floor {t.get('floor')}): posX={t.get('position_x')}, posY={t.get('position_y')}, status={t.get('status')}, is_deleted={t.get('is_deleted')}")
except urllib.error.HTTPError as e:
    print("Failed to fetch tables with service_role (HTTP Error):", e.code)
    print("Response body:", e.read().decode('utf-8'))
except Exception as e:
    print("Failed to fetch tables with service_role:", e)
