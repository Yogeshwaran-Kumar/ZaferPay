import requests

BASE_URL = "http://127.0.0.1:8000"

def test_flow():
    print("Testing Backend Flow...")
    
    # 1. Login userA
    print("1. Logging in userA...")
    resp = requests.post(f"{BASE_URL}/token", data={"username": "userA", "password": "password123"})
    if resp.status_code != 200:
        print("Login Failed:", resp.text)
        return
    token = resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    print("   Success. Token received.")

    # 2. Get Balance
    print("2. Fetching Profile...")
    resp = requests.get(f"{BASE_URL}/users/me", headers=headers)
    user_data = resp.json()
    print(f"   Success. Balance: {user_data['balance']}")
    
    # 3. Safe Transaction
    print("3. Testing SAFE Transaction (₹100)...")
    tx_data = {"receiver_upi_id": "shopC@mockbank", "amount": 100.0}
    resp = requests.post(f"{BASE_URL}/transactions/", json=tx_data, headers=headers)
    print("   Response:", resp.json())
    assert resp.json()["status"] == "SUCCESS"
    assert resp.json()["risk_score"] == "SAFE"
    
    # 4. High Risk Transaction (amount > 3x avg of 500 = 1500)
    # userA's profile initialized with avg=500. So 2000 should be high risk.
    print("4. Testing HIGH RISK Transaction (₹20,000)...")
    tx_data = {"receiver_upi_id": "shopC@mockbank", "amount": 20000.0}
    resp = requests.post(f"{BASE_URL}/transactions/", json=tx_data, headers=headers)
    print("   Response:", resp.json())
    # Depending on rules, might be WARN or HIGH. Logic says > 3x avg (1500) adds 50 risk.
    # Base risk 0. Sender risk 50. Total 0.6*50 = 30.
    # Receiver risk? Spike check. shopC has 10k balance. Receiving 20k is big spike? 
    # Receiver profile initialized empty? No, seed says user_id=db_user.id.
    # If risk is WARN (>=40) or HIGH (>=70).
    # 20k is > 5x receiver avg? Initial receiver avg is 0/0.
    # Let's see result.
    
    print("Backend Verification Complete.")

if __name__ == "__main__":
    test_flow()
