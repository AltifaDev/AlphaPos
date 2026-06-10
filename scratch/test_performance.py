import time
import urllib.request
import json
import concurrent.futures

BASE_URL = "http://127.0.0.1:8080/v1"

def fetch_sync():
    start = time.perf_counter()
    try:
        req = urllib.request.Request(f"{BASE_URL}/sync")
        with urllib.request.urlopen(req, timeout=5) as response:
            code = response.getcode()
            response.read()
            duration = time.perf_counter() - start
            return code, duration
    except Exception as e:
        return 500, time.perf_counter() - start

def post_order(table_num):
    payload = {
        "tableNumber": str(table_num),
        "total": 120.0,
        "items": [
            {"id": "test-item-1", "name": "Test Spring Rolls", "quantity": 1, "price": 120.0}
        ]
    }
    data = json.dumps(payload).encode("utf-8")
    start = time.perf_counter()
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/orders", 
            data=data,
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=5) as response:
            code = response.getcode()
            response.read()
            duration = time.perf_counter() - start
            return code, duration
    except Exception as e:
        return 500, time.perf_counter() - start

def run_performance_test():
    print("Starting Concurrency Performance Test...")
    print("Testing against running server at:", BASE_URL)
    
    # Warm up connection
    fetch_sync()
    
    # 20 concurrent clients fetching /v1/sync and 5 concurrent order submissions
    with concurrent.futures.ThreadPoolExecutor(max_workers=25) as executor:
        futures = []
        for i in range(20):
            futures.append(executor.submit(fetch_sync))
        for i in range(5):
            futures.append(executor.submit(post_order, (i % 5) + 1))
            
        results = [f.result() for f in futures]
        
    durations = [res[1] for res in results]
    avg_duration_ms = (sum(durations) / len(durations)) * 1000
    max_duration_ms = max(durations) * 1000
    min_duration_ms = min(durations) * 1000
    
    print(f"Total Requests Executed: {len(results)}")
    print(f"Average Response Time  : {avg_duration_ms:.2f} ms")
    print(f"Min Response Time      : {min_duration_ms:.2f} ms")
    print(f"Max Response Time      : {max_duration_ms:.2f} ms")
    
    success_count = sum(1 for res in results if res[0] == 200)
    print(f"Success Count          : {success_count}/{len(results)}")
    
    if avg_duration_ms < 15.0:
        print("Performance verification PASSED! Average response time is below 15ms.")
    else:
        print(f"Performance warning: Average response time is {avg_duration_ms:.2f}ms.")

if __name__ == "__main__":
    run_performance_test()
