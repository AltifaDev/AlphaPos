import re
import time
import sqlite3
import requests
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

def run_browser_test():
    print("Initializing Chrome in Headless mode...")
    chrome_options = Options()
    chrome_options.add_argument("--headless=new")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--window-size=1280,1024")
    chrome_options.set_capability('goog:loggingPrefs', {'browser': 'ALL'})
    
    service = Service(ChromeDriverManager().install())
    driver = webdriver.Chrome(service=service, options=chrome_options)
    
    try:
        url = "http://localhost:8080/?autoOnboard=true&table=5&token=table"
        print(f"Navigating to: {url}")
        driver.get(url)
        
        wait = WebDriverWait(driver, 15)
        
        # 1. Wait for automatic onboarding to finish.
        print("Waiting for automatic onboarding flow to complete and wizard to close...")
        
        def wizard_dismissed(d):
            try:
                wizard = d.find_element(By.ID, "onboardingWizard")
                return "active" not in wizard.get_attribute("class")
            except:
                return True
        
        try:
            wait.until(wizard_dismissed)
            print("Onboarding wizard dismissed. Main menu is now active.")
        except TimeoutException as e:
            print("Timeout waiting for onboarding wizard to dismiss!")
            print("Retrieving console logs from browser:")
            for entry in driver.get_log('browser'):
                print("  [BROWSER]", entry)
            raise e
        
        time.sleep(1)
        
        # 2. Wait for menu items to render and get the first one
        menu_items = wait.until(
            EC.presence_of_all_elements_located((By.CLASS_NAME, "menu-item-card"))
        )
        print(f"Found {len(menu_items)} menu items on the page.")
        
        first_item = menu_items[0]
        item_name = first_item.find_element(By.CLASS_NAME, "menu-item-title").text
        item_price = first_item.find_element(By.CLASS_NAME, "menu-item-price").text
        print(f"Clicking on first menu item: '{item_name}' ({item_price})")
        
        driver.execute_script("arguments[0].click();", first_item)
        
        # 3. Wait for product detail modal to open
        print("Waiting for product detail modal...")
        wait.until(EC.visibility_of_element_located((By.ID, "productDetailModal")))
        
        # 4. Select the first modifier option if available
        modifiers = driver.find_elements(By.CLASS_NAME, "modifier-option-item")
        if modifiers:
            print(f"Found {len(modifiers)} modifier options in the modal.")
            mod_name = modifiers[0].find_element(By.CSS_SELECTOR, "div.modifier-option-label span:nth-child(2)").text
            mod_price = modifiers[0].find_element(By.CLASS_NAME, "modifier-option-price").text
            print(f"Selecting modifier: '{mod_name}' ({mod_price})")
            
            driver.execute_script("arguments[0].click();", modifiers[0])
            time.sleep(0.5)
        else:
            print("No modifier options found for this item.")
            
        # 5. Click "Add to Order"
        add_btn = driver.find_element(By.ID, "modalAddBtn")
        print(f"Clicking add to cart: '{add_btn.text}'")
        driver.execute_script("arguments[0].click();", add_btn)
        
        # Wait for modal to hide
        print("Waiting for product modal to close...")
        wait.until(EC.invisibility_of_element_located((By.ID, "productDetailModal")))
        
        # Verify cart counter
        cart_count = driver.find_element(By.ID, "cartCount").text
        cart_total = driver.find_element(By.ID, "cartTotal").text
        print(f"Cart state: Count = {cart_count}, Total = {cart_total}")
        
        # 6. Open cart drawer
        print("Opening cart drawer...")
        driver.execute_script("app.toggleCartDrawer(true);")
        
        # Wait for cart drawer overlay to be visible
        wait.until(EC.visibility_of_element_located((By.ID, "cartDrawerOverlay")))
        
        # 7. Click "Submit Order" button
        submit_btn = driver.find_element(By.ID, "submitOrderBtn")
        print(f"Submitting order by clicking: '{submit_btn.text}'")
        driver.execute_script("arguments[0].click();", submit_btn)
        
        # Wait for server response and processing
        print("Waiting for order submission to complete...")
        time.sleep(3)
        
        # Read logs outputted to the headlessLog div on screen
        try:
            logs_el = driver.find_element(By.ID, "headlessLogs")
            logs = logs_el.text
            print("\n--- Browser Headless Logs ---")
            print(logs)
            print("-----------------------------\n")
        except Exception as e:
            print("Could not retrieve headless logs element:", str(e))
            
    except Exception as e:
        print("Exception occurred during test execution:")
        print(type(e), str(e))
        print("Retrieving console logs from browser:")
        try:
            for entry in driver.get_log('browser'):
                print("  [BROWSER]", entry)
        except Exception as log_err:
            print("Could not retrieve browser logs:", str(log_err))
        raise e
    finally:
        driver.quit()

def check_db():
    # Attempt to read Supabase configuration
    supabase_url = ""
    supabase_key = ""
    merchant_id = ""
    try:
        with open("config.js", "r") as f:
            content = f.read()
            url_match = re.search(r"supabaseUrl:\s*['\"]([^'\"]+)['\"]", content)
            key_match = re.search(r"supabaseKey:\s*['\"]([^'\"]+)['\"]", content)
            merchant_match = re.search(r"merchantId:\s*['\"]([^'\"]+)['\"]", content)
            if url_match: supabase_url = url_match.group(1)
            if key_match: supabase_key = key_match.group(1)
            if merchant_match: merchant_id = merchant_match.group(1)
    except Exception as e:
        print("Could not read config.js:", str(e))

    if supabase_url and supabase_key:
        print("\n=== Supabase Online Database Order Verification ===")
        try:
            headers = {
                "apikey": supabase_key,
                "Authorization": f"Bearer {supabase_key}",
                "Content-Type": "application/json"
            }
            if merchant_id:
                headers["x-merchant-id"] = merchant_id
            
            # 1. Get latest active session for Table 5
            session_res = requests.get(
                f"{supabase_url}/rest/v1/table_sessions?table_number=eq.5&is_active=eq.1&order=created_at.desc&limit=1",
                headers=headers
            )
            if session_res.status_code == 200 and session_res.json():
                session = session_res.json()[0]
                print(f"Latest Session: ID={session.get('id')}, Table={session.get('table_number')}, Guests={session.get('guest_count')}, Active={session.get('is_active')}, Created={session.get('created_at')}")
            else:
                print("No active table 5 session found in Supabase.")
                
            # 2. Get latest order for Table 5
            order_res = requests.get(
                f"{supabase_url}/rest/v1/orders?table_number=eq.5&order=created_at.desc&limit=1",
                headers=headers
            )
            if order_res.status_code == 200 and order_res.json():
                order = order_res.json()[0]
                print(f"Latest Order: ID={order.get('id')}, Num={order.get('order_number')}, Total=฿{order.get('total')}, Status={order.get('status')}, Created={order.get('created_at')}")
                
                # 3. Get order items
                items_res = requests.get(
                    f"{supabase_url}/rest/v1/order_items?order_id=eq.{order.get('id')}",
                    headers=headers
                )
                if items_res.status_code == 200:
                    items = items_res.json()
                    print("Order Items:")
                    for item in items:
                        print(f"  - Item: {item.get('item_name')} (ID: {item.get('item_id')}), Qty: {item.get('quantity')}, Price: ฿{item.get('price')}, Notes: '{item.get('notes')}'")
                        
                        # 4. Get modifiers
                        mods_res = requests.get(
                            f"{supabase_url}/rest/v1/order_item_modifiers?order_item_id=eq.{item.get('id')}",
                            headers=headers
                        )
                        if mods_res.status_code == 200:
                            mods = mods_res.json()
                            if mods:
                                print("    Modifiers Selected:")
                                for mod in mods:
                                    print(f"      * Modifier ID: {mod.get('modifier_id')}, Price: ฿{mod.get('price')}")
                else:
                    print("Failed to fetch order items from Supabase.")
            else:
                print("No orders found in Supabase.")
        except Exception as e:
            print("Error checking Supabase:", str(e))

    print("\n=== SQLite Local Database Order Verification ===")
    try:
        conn = sqlite3.connect("alphapos.db")
        cursor = conn.cursor()
        
        # 1. Get latest active session for Table 5
        cursor.execute("SELECT id, table_number, guest_count, is_active, created_at FROM table_sessions WHERE table_number = '5' AND is_active = 1 ORDER BY created_at DESC LIMIT 1")
        session = cursor.fetchone()
        if session:
            print(f"Latest Session: ID={session[0]}, Table={session[1]}, Guests={session[2]}, Active={session[3]}, Created={session[4]}")
        else:
            print("No active table 5 session found in SQLite.")
            
        # 2. Get latest order for Table 5
        cursor.execute("SELECT id, order_number, table_number, total, status, created_at FROM orders WHERE table_number = '5' ORDER BY created_at DESC LIMIT 1")
        order = cursor.fetchone()
        if order:
            print(f"Latest Order: ID={order[0]}, Num={order[1]}, Total=฿{order[3]}, Status={order[4]}, Created={order[5]}")
            order_id = order[0]
            
            # 3. Get order items
            cursor.execute("SELECT id, item_name, quantity, price, item_id FROM order_items WHERE order_id = ?", (order_id,))
            items = cursor.fetchall()
            print("Order Items:")
            for item in items:
                print(f"  - Item: {item[1]} (ID: {item[4]}), Qty: {item[2]}, Price: ฿{item[3]}")
                item_id = item[0]
                
                # 4. Get modifiers
                cursor.execute("SELECT id, modifier_id, price FROM order_item_modifiers WHERE order_item_id = ?", (item_id,))
                mods = cursor.fetchall()
                if mods:
                    print("    Modifiers Selected:")
                    for mod in mods:
                        print(f"      * Modifier ID: {mod[1]}, Price: ฿{mod[2]}")
        else:
            print("No orders found in SQLite.")
        conn.close()
    except Exception as e:
        print("Error checking SQLite:", str(e))

if __name__ == "__main__":
    run_browser_test()
    check_db()
