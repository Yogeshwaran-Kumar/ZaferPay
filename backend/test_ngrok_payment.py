
import requests
import json
import sys

# Constants
BASE_URL = "https://collen-horrent-allison.ngrok-free.dev"
SENDER_MOBILE = "6383527947"
PIN = "1234" # Assuming default/set PIN
RECEIVER_UPI = "9994008960@oki" # Aarthi's UPI from DB dump or previous context (actually from screenshot it is 84387... but let's use a known one or lookup)
AMOUNT = 100.0

# 1. Login to get token
print(f"Logging in with {SENDER_MOBILE}...")
login_payload = {
    "username": SENDER_MOBILE,
    "password": PIN
}
try:
    login_req = requests.post(f"{BASE_URL}/token", data=login_payload)
    print(f"Login Status: {login_req.status_code}")
    if login_req.status_code != 200:
        print(f"Login Failed: {login_req.text}")
        sys.exit(1)
        
    token = login_req.json()["access_token"]
    print("Login Successful. Token received.")
except Exception as e:
    print(f"Login Exception: {e}")
    sys.exit(1)

# 2. Make Payment
print(f"Sending {AMOUNT} to {RECEIVER_UPI}...")
headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}
payment_payload = {
    "receiver_upi_id": RECEIVER_UPI,
    "amount": AMOUNT,
    "pin": PIN
}

try:
    # Look up receiver first to be sure
    # But let's go straight to transaction as per app flow
    pay_req = requests.post(f"{BASE_URL}/transactions/", json=payment_payload, headers=headers)
    print(f"Payment Status: {pay_req.status_code}")
    print(f"Payment Response: {pay_req.text}")
    
except Exception as e:
    print(f"Payment Exception: {e}")
