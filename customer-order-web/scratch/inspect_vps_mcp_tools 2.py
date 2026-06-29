import urllib.request
import urllib.error
import json

SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE"
SUPABASE_SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q"

def test_mcp(key, name):
    url = "http://119.59.99.163:54321/mcp"
    payload = {
        "jsonrpc": "2.0",
        "method": "tools/list",
        "params": {},
        "id": 1
    }
    
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers={
        "Content-Type": "application/json",
        "apikey": key,
        "Authorization": f"Bearer {key}"
    }, method="POST")
    
    try:
        with urllib.request.urlopen(req) as response:
            print(f"=== Success with {name} ===")
            print("Response:", json.dumps(json.loads(response.read().decode('utf-8')), indent=2))
    except urllib.error.HTTPError as e:
        print(f"=== Error with {name} {e.code}: {e.reason} ===")
        try:
            print("Body:", e.read().decode('utf-8'))
        except Exception:
            pass
    except Exception as e:
        print(f"Connection Error with {name}:", e)

if __name__ == "__main__":
    print("Testing with Anon Key:")
    test_mcp(SUPABASE_ANON_KEY, "Anon Key")
    print("\nTesting with Service Key:")
    test_mcp(SUPABASE_SERVICE_KEY, "Service Key")
