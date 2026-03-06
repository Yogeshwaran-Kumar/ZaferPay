import requests
data = {
    "username": "Kavitha",
    "mobile_number": "1122334455",
    "email": None,
    "pin": "1234",
    "has_bank_account": False
}
try:
    r = requests.post("http://127.0.0.1:8000/auth/signup", json=data)
    print(r.status_code)
    print(r.text)
except Exception as e:
    print(f"Exception: {e}")
