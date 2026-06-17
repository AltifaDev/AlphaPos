import urllib.request
import json

url = "https://your-supabase-project.supabase.co/rest/v1/menu_items"
anon_key = "your-anon-key"

req = urllib.request.Request(
    url,
    headers={
        "apikey": anon_key,
        "Authorization": f"Bearer {anon_key}"
    },
    method="GET"
)

try:
    with urllib.request.urlopen(req) as response:
        print("Status:", response.status)
        print("Data:", response.read().decode("utf-8"))
except Exception as e:
    print("Error:", e)
    if hasattr(e, 'read'):
        print(e.read().decode("utf-8"))
