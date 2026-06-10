import urllib.request
import json
import time

BASE_URL = "http://127.0.0.1:8080/v1"

def test_get_employees():
    print("Testing GET /v1/employees...")
    req = urllib.request.urlopen(f"{BASE_URL}/employees")
    data = json.loads(req.read().decode())
    assert len(data) >= 2
    usernames = [x["username"] for x in data]
    assert "somchai" in usernames
    assert "somsri" in usernames
    print("GET /v1/employees passed!")

def test_get_tables():
    print("Testing GET /v1/tables...")
    req = urllib.request.urlopen(f"{BASE_URL}/tables")
    data = json.loads(req.read().decode())
    assert len(data) == 10
    tables_num = [x["tableNumber"] for x in data]
    assert "1" in tables_num
    assert "VIP 1" in tables_num
    assert "301 (ROOF)" in tables_num
    print("GET /v1/tables passed!")

def test_session_and_order_sync():
    print("Testing Session and Order Sync...")
    import uuid
    
    # 1. Open session on Table 4
    open_payload = json.dumps({"table_number": "4", "guest_count": 5}).encode()
    req = urllib.request.Request(f"{BASE_URL}/sessions/open", data=open_payload, method="POST")
    res = urllib.request.urlopen(req)
    res_data = json.loads(res.read().decode())
    assert res_data["success"] is True
    
    # 2. Get tables, verify Table 4 is occupied
    req = urllib.request.urlopen(f"{BASE_URL}/tables")
    tables = json.loads(req.read().decode())
    t4 = next(x for x in tables if x["tableNumber"] == "4")
    assert t4["status"] == "occupied"
    assert t4["guestCount"] == 5
    
    # 3. Create an order for Table 4
    order_id = str(uuid.uuid4())
    order_payload = json.dumps({
        "id": order_id,
        "orderNumber": f"ORD-TEST-{str(uuid.uuid4().int)[:4]}",
        "tableNumber": "4",
        "total": 350.0,
        "items": [
            {"name": "Tom Yum Goong", "quantity": 1, "price": 280.0, "status": "cooking", "item_id": "app3"},
            {"name": "Traditional Thai Iced Tea", "quantity": 1, "price": 70.0, "status": "cooking", "item_id": "drink1"}
        ]
    }).encode()
    req = urllib.request.Request(f"{BASE_URL}/orders", data=order_payload, method="POST")
    res = urllib.request.urlopen(req)
    assert json.loads(res.read().decode())["success"] is True
    
    # 4. Verify Table 4 total is updated
    req = urllib.request.urlopen(f"{BASE_URL}/tables")
    tables = json.loads(req.read().decode())
    t4 = next(x for x in tables if x["tableNumber"] == "4")
    assert t4["currentTotal"] == 350.0
    
    # 5. Close session on Table 4
    close_payload = json.dumps({"table_number": "4"}).encode()
    req = urllib.request.Request(f"{BASE_URL}/sessions/close", data=close_payload, method="POST")
    res = urllib.request.urlopen(req)
    assert json.loads(res.read().decode())["success"] is True
    
    # 6. Verify Table 4 is vacant again
    req = urllib.request.urlopen(f"{BASE_URL}/tables")
    tables = json.loads(req.read().decode())
    t4 = next(x for x in tables if x["tableNumber"] == "4")
    assert t4["status"] == "vacant"
    print("Session and Order Sync passed!")

def test_timecard_sync():
    print("Testing Timecard Sync...")
    import uuid
    tc_id = str(uuid.uuid4())
    
    # 1. Clock In
    clockin_payload = json.dumps({
        "id": tc_id,
        "employee_id": "11111111-1111-1111-1111-111111111111",
        "employee_name": "Somchai Suksabai",
        "clock_in": time.time(),
        "status": "approved",
        "clock_in_confidence": 98.5
    }).encode()
    req = urllib.request.Request(f"{BASE_URL}/timecards", data=clockin_payload, method="POST")
    res = urllib.request.urlopen(req)
    assert json.loads(res.read().decode())["success"] is True
    
    # 2. Verify active timecard in history
    req = urllib.request.urlopen(f"{BASE_URL}/timecards?employee_id=11111111-1111-1111-1111-111111111111")
    history = json.loads(req.read().decode())
    active = next(x for x in history if x["id"] == tc_id)
    assert active["clockOut"] is None or active["clockOut"] == 0
    assert active["status"] == "approved"
    
    # 3. Clock Out
    clockout_payload = json.dumps({
        "id": tc_id,
        "employee_id": "11111111-1111-1111-1111-111111111111",
        "employee_name": "Somchai Suksabai",
        "clock_in": active["clockIn"],
        "clock_out": time.time() + 3600, # 1 hour later
        "status": "approved",
        "clock_out_confidence": 97.2
    }).encode()
    req = urllib.request.Request(f"{BASE_URL}/timecards", data=clockout_payload, method="POST")
    res = urllib.request.urlopen(req)
    assert json.loads(res.read().decode())["success"] is True
    
    # 4. Verify completed timecard in history
    req = urllib.request.urlopen(f"{BASE_URL}/timecards?employee_id=11111111-1111-1111-1111-111111111111")
    history = json.loads(req.read().decode())
    completed = next(x for x in history if x["id"] == tc_id)
    assert completed["clockOut"] is not None and completed["clockOut"] > 0
    print("Timecard Sync passed!")


if __name__ == "__main__":
    test_get_employees()
    test_get_tables()
    test_session_and_order_sync()
    test_timecard_sync()
    print("All integration tests passed successfully!")
