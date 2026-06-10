import json

with open("scratch/supabase_swagger.json") as f:
    schema = json.load(f)

definitions = schema.get("definitions", {})
table_sessions = definitions.get("table_sessions", {})
properties = table_sessions.get("properties", {})
print("table_sessions columns:")
for prop, details in properties.items():
    print(f" - {prop}: {details.get('type')}")

print("\ntables columns:")
tables = definitions.get("tables", {})
properties = tables.get("properties", {})
for prop, details in properties.items():
    print(f" - {prop}: {details.get('type')}")
