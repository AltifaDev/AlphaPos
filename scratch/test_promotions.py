import urllib.request
import json
import uuid

BASE_URL = "http://127.0.0.1:8080/v1"

def test_promotions_crud():
    print("--- Starting Promotions CRUD Test ---")
    
    # 1. GET promotions (should be empty or return current list)
    try:
        req = urllib.request.urlopen(f"{BASE_URL}/promotions")
        data = json.loads(req.read().decode('utf-8'))
        print(f"Initial promotions count: {len(data)}")
    except Exception as e:
        print(f"Failed to fetch promotions: {e}")
        return
        
    # 2. POST a promotion
    promo_id = str(uuid.uuid4())
    payload = {
        "id": promo_id,
        "title": "Special Matcha Green Tea Latte",
        "promoDescription": "Try our new premium Uji Matcha latte made with organic oats milk.",
        "imageData": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", # 1x1 png base64
        "isActive": True,
        "isDeleted": False
    }
    
    try:
        req_post = urllib.request.Request(
            f"{BASE_URL}/promotions",
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        res_post = urllib.request.urlopen(req_post)
        res_data = json.loads(res_post.read().decode('utf-8'))
        print(f"POST promotion result: {res_data}")
        assert res_data.get("success") == True, "Post failed"
    except Exception as e:
        print(f"Failed to create promotion: {e}")
        return

    # 3. GET promotions again to verify it is inserted
    try:
        req = urllib.request.urlopen(f"{BASE_URL}/promotions")
        data = json.loads(req.read().decode('utf-8'))
        print(f"Promotions count after POST: {len(data)}")
        found = False
        for p in data:
            if p["id"] == promo_id:
                found = True
                print(f"Successfully verified inserted promotion: {p['title']}")
                break
        assert found, "Promotion not found in list"
    except Exception as e:
        print(f"Failed to verify inserted promotion: {e}")
        return

    # 4. DELETE the promotion
    try:
        req_del = urllib.request.Request(
            f"{BASE_URL}/promotions/delete",
            data=json.dumps({"id": promo_id}).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        res_del = urllib.request.urlopen(req_del)
        res_data = json.loads(res_del.read().decode('utf-8'))
        print(f"DELETE promotion result: {res_data}")
        assert res_data.get("success") == True, "Delete failed"
    except Exception as e:
        print(f"Failed to delete promotion: {e}")
        return

    # 5. Verify it is deleted
    try:
        req = urllib.request.urlopen(f"{BASE_URL}/promotions")
        data = json.loads(req.read().decode('utf-8'))
        found = False
        for p in data:
            if p["id"] == promo_id:
                found = True
                break
        assert not found, "Promotion should be deleted but was found in list"
        print("Success! Promotion CRUD flow is fully verified on the Python server.")
    except Exception as e:
        print(f"Verification after delete failed: {e}")
        return

if __name__ == "__main__":
    test_promotions_crud()
