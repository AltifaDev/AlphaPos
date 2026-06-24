import urllib.request
import urllib.error

def test_mcp():
    url = "http://119.59.99.163:54321/mcp"
    req = urllib.request.Request(url, headers={
        "Content-Type": "application/json"
    })
    try:
        with urllib.request.urlopen(req) as response:
            print("Status:", response.status)
            print("Response:", response.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code}: {e.reason}")
        try:
            print("Body:", e.read().decode('utf-8'))
        except Exception:
            pass
    except Exception as e:
        print("Connection Error:", e)

if __name__ == "__main__":
    test_mcp()
