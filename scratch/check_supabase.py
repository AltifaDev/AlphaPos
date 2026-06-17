import requests
import json

supabase_url = "https://your-supabase-project.supabase.co"
supabase_key = "your-anon-key"

headers = {
    "apikey": supabase_key,
    "Authorization": f"Bearer {supabase_key}",
    "Content-Type": "application/json",
    "x-merchant-id": "your-merchant-uuid"
}

res = requests.get(
    f"{supabase_url}/rest/v1/orders?order=created_at.desc&limit=3",
    headers=headers
)

if res.status_code == 200:
    print(json.dumps(res.json(), indent=2))
else:
    print(f"Error {res.status_code}: {res.text}")
