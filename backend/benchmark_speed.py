import time
import requests
import json
import statistics

# Configuration
BASE_URL = "http://localhost:8000"
SENDER_TOKEN = "" # Fill in with valid token
RECEIVER_UPI = "testuser2@upi"
AMOUNT = 100.0
PIN = "123456"

def get_token():
    # Helper to get a token if needed, or use a hardcoded one for testing
    pass

def benchmark_transaction(skip_check=False):
    payload = {
        "receiver_upi_id": RECEIVER_UPI,
        "amount": AMOUNT,
        "pin": PIN,
        "idempotency_key": f"bench_{int(time.time()*1000)}",
        "skip_fraud_check": skip_check,
        "acknowledged_risk": "SAFE" if skip_check else None
    }
    
    headers = {
        "Authorization": f"Bearer {SENDER_TOKEN}",
        "Content-Type": "application/json",
        "X-Timestamp": str(int(time.time())),
        "X-Signature": "mock_sig" # Logic might need adjustment for HMAC
    }
    
    start = time.perf_counter()
    # Note: verify_integrity would normally block this if signatures don't match
    # For local benchmarking, we might need a test mode or bypass in backend
    response = requests.post(f"{BASE_URL}/transactions/", json=payload, headers=headers)
    end = time.perf_counter()
    
    return (end - start) * 1000, response.status_code

def run_suite(count=5):
    print(f"Running benchmark with {count} iterations...")
    
    # Standard Flow
    std_times = []
    for i in range(count):
        t, s = benchmark_transaction(skip_check=False)
        print(f"Standard #{i+1}: {t:.2f}ms (Status: {s})")
        std_times.append(t)
    
    # Optimized Flow (Skip check)
    opt_times = []
    for i in range(count):
        t, s = benchmark_transaction(skip_check=True)
        print(f"Optimized #{i+1}: {t:.2f}ms (Status: {s})")
        opt_times.append(t)
        
    print("\n--- RESULTS ---")
    print(f"Standard Mean: {statistics.mean(std_times):.2f}ms")
    print(f"Optimized Mean: {statistics.mean(opt_times):.2f}ms")
    print(f"Speed Improvement: {((statistics.mean(std_times) - statistics.mean(opt_times)) / statistics.mean(std_times)) * 100:.1f}%")

if __name__ == "__main__":
    # In a real environment, we'd need valid auth and signatures
    print("Benchmark script ready. Requires valid SENDER_TOKEN and HMAC bypass for local run.")
