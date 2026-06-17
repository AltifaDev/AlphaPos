import urllib.request
import json

supabase_url = 'https://sdmtkixrqkmwcpwoisrg.supabase.co'
supabase_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws'
merchant_id = '163350b0-056d-4d5e-b5d4-24e7aac5ab6d'

headers = {
    'apikey': supabase_key,
    'Authorization': f'Bearer {supabase_key}',
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
    'x-merchant-id': merchant_id
}

url = f"{supabase_url}/rest/v1/promotions?id=eq.e0abe3fd-2d10-4abd-8736-6c4f865d0837"
payload = json.dumps({
    "is_active": 1
}).encode('utf-8')

req = urllib.request.Request(url, headers=headers, data=payload, method="PATCH")

try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        print("Successfully activated the Beer promotion in Supabase.")
        print(data)
except Exception as e:
    print("Failed to update promotion in Supabase:", str(e))
