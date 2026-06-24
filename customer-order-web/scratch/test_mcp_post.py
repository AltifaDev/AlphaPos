import urllib.request
import urllib.error
import json

def test_mcp_post():
    url = "http://119.59.99.163:54321/mcp"
    payload = {
        "jsonrpc": "2.0",
        "method": "tools/list",
        "params": {},
        "id": 1
    }
    
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers={
        "Content-Type": "application/json"
    }, method="POST")
    
    try:
        with urllib.request.urlopen(req) as response:
            print("Status:", response.status)
            print("Response:", json.dumps(json.loads(response.read().decode('utf-8')), indent=2))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.reason}")
        try:
            print("Body:", e.read().decode('utf-8'))
        except Exception:
            pass
    except Exception as e:
        print("Connection Error:", e)

if __name__ == "__main__":
    test_mcp_post()
