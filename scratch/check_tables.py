import urllib.request
import json

url = "https://sdmtkixrqkmwcpwoisrg.supabase.co/rest/v1/"
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNkbXRraXhycWttd2Nwd29pc3JnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NDIxNjAsImV4cCI6MjA5NjQxODE2MH0.rjLwVE0ShXIFoT0k982XO_lVCQMsA4uTKMW1Su-NUws"

tables = [
    "roles", "users", "user_sessions", "tables", "table_sessions",
    "suppliers", "inventory_items", "inventory_transactions", "categories",
    "menu_items", "recipes", "modifier_groups", "menu_item_modifier_groups",
    "modifiers", "orders", "order_items", "order_item_modifiers", "payments",
    "employees", "employee_shifts", "timecards", "payroll_periods",
    "payroll_slips", "register_sessions", "service_requests"
]

results = {}
for table in tables:
    req = urllib.request.Request(
        f"{url}{table}?limit=1",
        headers={
            "apikey": anon_key,
            "Authorization": f"Bearer {anon_key}"
        },
        method="GET"
    )
    try:
        with urllib.request.urlopen(req) as response:
            results[table] = response.status
    except urllib.error.HTTPError as e:
        results[table] = e.code
    except Exception as e:
        results[table] = str(e)

print(json.dumps(results, indent=2))
