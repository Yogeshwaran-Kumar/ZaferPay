import requests
import sys

BASE_URL = "http://127.0.0.1:8000"

def test_single_device_login():
    print("Testing Single Device Login...")

    # 1. Login with Device 1
    print("\n1. Login Device 1 (Initial)...")
    resp1 = requests.post(f"{BASE_URL}/token", data={"username": "userA", "password": "password123"}, headers={"X-Device-ID": "device_1"})
    if resp1.status_code != 200:
        print(f"FAILED: Device 1 Login failed: {resp1.status_code} {resp1.text}")
        return False
    token1 = resp1.json()["access_token"]
    print("SUCCESS: Device 1 Logged in.")

    # Verify Token 1 works
    resp1_me = requests.get(f"{BASE_URL}/users/me", headers={"Authorization": f"Bearer {token1}"})
    if resp1_me.status_code != 200:
         print(f"FAILED: Device 1 Token invalid: {resp1_me.status_code}")
         return False

    # 2. Login with Device 2 (Should Fail)
    print("\n2. Login Device 2 (Conflict check)...")
    resp2 = requests.post(f"{BASE_URL}/token", data={"username": "userA", "password": "password123"}, headers={"X-Device-ID": "device_2"})
    if resp2.status_code == 409:
        print("SUCCESS: Device 2 Login Blocked (409 Conflict).")
    else:
        print(f"FAILED: Device 2 Login should be 409, got {resp2.status_code}")
        return False

    # 3. Login with Device 2 (Force Logout)
    print("\n3. Login Device 2 (Force Logout)...")
    resp3 = requests.post(f"{BASE_URL}/token?force_logout=true", data={"username": "userA", "password": "password123"}, headers={"X-Device-ID": "device_2"})
    if resp3.status_code != 200:
        print(f"FAILED: Device 2 Force Login failed: {resp3.status_code} {resp3.text}")
        return False
    token2 = resp3.json()["access_token"]
    print("SUCCESS: Device 2 Force Logged in.")

    # 4. Verify Device 1 Token is now Invalid
    print("\n4. Verify Device 1 Token Invalid...")
    resp1_me_retry = requests.get(f"{BASE_URL}/users/me", headers={"Authorization": f"Bearer {token1}"})
    if resp1_me_retry.status_code == 401:
        print("SUCCESS: Device 1 Token Invalidated.")
    else:
        print(f"FAILED: Device 1 Token should be 401, got {resp1_me_retry.status_code}")
        return False
    
    # 5. Verify Device 2 Token works
    print("\n5. Verify Device 2 Token Valid...")
    resp2_me = requests.get(f"{BASE_URL}/users/me", headers={"Authorization": f"Bearer {token2}"})
    if resp2_me.status_code == 200:
        print("SUCCESS: Device 2 Token Valid.")
    else:
         print(f"FAILED: Device 2 Token invalid: {resp2_me.status_code}")
         return False

    # 6. Logout Device 2
    print("\n6. Logout Device 2...")
    resp_logout = requests.post(f"{BASE_URL}/logout", headers={"Authorization": f"Bearer {token2}"})
    if resp_logout.status_code == 200:
        print("SUCCESS: Device 2 Logged out.")
    else:
        print(f"FAILED: Logout failed {resp_logout.status_code}")
        return False

    print("\nALL TESTS PASSED!")
    return True

if __name__ == "__main__":
    try:
        success = test_single_device_login()
        if not success:
            sys.exit(1)
    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)
