import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager

def run_no_token_test():
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
        url = "https://alphapos.altifadev.workers.dev/?table=5"
        print(f"Navigating to: {url}")
        driver.get(url)
        
        print("Waiting 4 seconds for page load...")
        time.sleep(4)

        try:
            btn = driver.find_element("id", "startOrderBtn")
            if btn.is_displayed():
                print("Clicking startOrderBtn to enter main menu...")
                btn.click()
                print("Waiting 4 seconds for transition...")
                time.sleep(4)
        except Exception as btn_err:
            print("No startOrderBtn click needed or failed:", btn_err)
        
        print("Saving screenshot to scratch/no_token_verification.png...")
        driver.save_screenshot("scratch/no_token_verification.png")
        
        print("\n--- Browser Console Logs ---")
        logs = driver.get_log('browser')
        if not logs:
            print("No console logs found.")
        else:
            for entry in logs:
                print(f"  [{entry.get('level')}] {entry.get('message')}")
        print("----------------------------\n")
        
    except Exception as e:
        print("Exception occurred during test execution:")
        print(type(e), str(e))
    finally:
        driver.quit()

if __name__ == "__main__":
    run_no_token_test()
