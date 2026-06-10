import urllib.request
import json

url = "https://sdmtkixrqkmwcpwoisrg.supabase.co/rest/v1/menu_items"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws"

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
