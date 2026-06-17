import time
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from webdriver_manager.chrome import ChromeDriverManager
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def run_verify():
    print("Initializing Chrome in Headless mode for verification...")
    chrome_options = Options()
    chrome_options.add_argument("--headless=new")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.set_capability('goog:loggingPrefs', {'browser': 'ALL'})
    
    service = Service(ChromeDriverManager().install())
    driver = webdriver.Chrome(service=service, options=chrome_options)
    
    try:
        url = "http://localhost:8080/?autoOnboard=true&table=3"
        print(f"Navigating to: {url}")
        driver.get(url)
        
        print("Waiting for promotions slider to load video...")
        wait = WebDriverWait(driver, 10)
        
        # Wait until video tag is present in the promotions slider
        video_el = wait.until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "#promotionsSlider video"))
        )
        
        print("\n--- FOUND VIDEO ELEMENT ---")
        print("Outer HTML:", video_el.get_attribute("outerHTML"))
        print("Src attribute:", video_el.get_attribute("src"))
        print("Autoplay:", video_el.get_attribute("autoplay"))
        print("Muted:", video_el.get_attribute("muted"))
        print("Loop:", video_el.get_attribute("loop"))
        
        print("\n--- BROWSER CONSOLE LOGS ---")
        logs = driver.get_log('browser')
        if not logs:
            print("No console logs found.")
        for entry in logs:
            print(f"  [{entry['level']}] {entry['message']}")
            
    except Exception as e:
        print("Error during verification:", str(e))
        print("\n--- BROWSER CONSOLE LOGS ON FAILURE ---")
        try:
            for entry in driver.get_log('browser'):
                print(f"  [{entry['level']}] {entry['message']}")
        except:
            pass
    finally:
        driver.quit()

if __name__ == "__main__":
    run_verify()
