
import random
from datetime import datetime, timedelta

# Constants
RISK_THRESHOLD_HIGH = 80
RISK_THRESHOLD_WARN = 50

transactions = []

def generate_transaction(i):
    # Randomize inputs
    tx_id = f"TXN{100000+i}"
    
    # 1. Amount
    # Weighted choice to trigger high value rules
    amount = random.choice([
        random.uniform(10, 500),    # Small
        random.uniform(500, 1999),  # Medium
        random.uniform(2001, 4999), # High (Triggers F8)
        random.uniform(5001, 10000) # Very High (Triggers F7)
    ])
    amount = round(amount, 2)
    
    # 2. Time
    # 10% chance of night owl (3-5 AM)
    is_night_owl = random.random() < 0.10
    hour = random.randint(3, 5) if is_night_owl else random.choice(list(range(6, 23)) + [0, 1, 2])
    
    # 3. Relationship (Trust Depth)
    # 0 = Stranger, 1 = Friend, 2 = FoF
    trust_depth = random.choice([0, 0, 0, 1, 2]) # Bias towards strangers for risk
    
    # 4. Velocity
    # >5 triggers F1
    recent_txns = random.choice([0, 1, 2, 3, 4, 5, 8])
    
    # 5. Loop (Circular)
    is_loop = random.random() < 0.05
    
    # 6. Dormant
    # >30 days inactive
    days_inactive = random.choice([1, 5, 10, 20])
    if random.random() < 0.05:
        days_inactive = random.randint(31, 60)
        
    # 7. Average Amount (for Spike check)
    avg_amount = random.uniform(100, 1000)
    
    # 8. AI Score
    # < -0.2 is bad
    ai_score = random.uniform(-0.5, 0.5)
    
    # --- LOGIC APPLICATION (Mirroring fraud_engine.py) ---
    risk_score = 0
    violations = []
    status = "SAFE"
    
    # STAGE 1: HARD RULES (Reflexes) - Return immediately if hit
    
    # F1: Velocity
    if recent_txns >= 5:
        return {
            "id": tx_id, "amount": amount, "hour": hour, "trust": trust_depth,
            "velocity": recent_txns, "loop": is_loop, "inactive": days_inactive,
            "avg": round(avg_amount, 2), "ai": round(ai_score, 2),
            "status": "HIGH", "reason": "F1_VELOCITY_LIMIT_EXCEEDED (Block)",
            "score": 100 # Maxed out
        }
        
    # F2: Circular
    if is_loop:
        risk_score += 40
        violations.append("F2_CIRCULAR_LOOP")
        
    # F3: Dormant
    if days_inactive > 30 and amount > 500:
        return {
            "id": tx_id, "amount": amount, "hour": hour, "trust": trust_depth,
            "velocity": recent_txns, "loop": is_loop, "inactive": days_inactive,
            "avg": round(avg_amount, 2), "ai": round(ai_score, 2),
            "status": "HIGH", "reason": "F3_DORMANT_ACCOUNT_SPIKE (Block)",
            "score": 100
        }
    
    # F5: Ticket Spike
    if amount > (avg_amount * 3):
        risk_score += 50
        violations.append("F5_AMOUNT_SPIKE")
        
    # F9: Night Owl
    if 3 <= hour <= 5:
        risk_score += 25
        violations.append("F9_UNUSUAL_TIME")
        
    # STAGE 2: SOCIAL GRAPH
    if trust_depth == 1:
        risk_score -= 10
    elif trust_depth == 0: # Stranger
        risk_score += 20
        violations.append("F12_STRANGER")
        
        # F8: Stranger High Value
        if amount > 2000:
            risk_score += 30
            violations.append("F8_HIGH_VALUE_STRANGER")
            
        # F7: Untrusted Receiver High Value (Block)
        if amount > 5000:
            return {
                "id": tx_id, "amount": amount, "hour": hour, "trust": trust_depth,
                "velocity": recent_txns, "loop": is_loop, "inactive": days_inactive,
                "avg": round(avg_amount, 2), "ai": round(ai_score, 2),
                "status": "HIGH", "reason": "F7_UNTRUSTED_RECEIVER_HIGH_VALUE (Block)",
                "score": 100
            }

    # STAGE 3: AI
    if ai_score < -0.2:
        risk_score += 65
        violations.append("F4_AI_ANOMALY")
    elif ai_score < 0:
        risk_score += 20
        
    # Final Calc
    risk_score = max(0, min(100, risk_score))
    
    if risk_score >= RISK_THRESHOLD_HIGH:
        status = "HIGH"
    elif risk_score >= RISK_THRESHOLD_WARN:
        status = "WARN"
    else:
        status = "SAFE"
        
    reason = ", ".join(violations) if violations else "Normal Activity"
    if status == "HIGH" and not reason: reason = "Cumulative High Risk"
    
    return {
        "id": tx_id, "amount": amount, "hour": hour, "trust": trust_depth,
        "velocity": recent_txns, "loop": is_loop, "inactive": days_inactive,
        "avg": round(avg_amount, 2), "ai": round(ai_score, 2),
        "status": status, "reason": reason, "score": risk_score
    }

# Generate 200 transactions
for i in range(200):
    transactions.append(generate_transaction(i))

# Generate HTML
html = """<!DOCTYPE html>
<html>
<head>
<style>
    body { font-family: sans-serif; background: #f4f4f9; padding: 20px; }
    table { width: 100%; border-collapse: collapse; box-shadow: 0 4px 8px rgba(0,0,0,0.1); background: white; }
    th { background: #333; color: white; padding: 12px; text-align: left; position: sticky; top: 0; }
    td { padding: 10px; border-bottom: 1px solid #ddd; font-size: 14px; }
    tr:nth-child(even) { background-color: #f9f9f9; }
    .status-SAFE { background-color: #d4edda; color: #155724; font-weight: bold; padding: 4px 8px; border-radius: 4px; }
    .status-WARN { background-color: #fff3cd; color: #856404; font-weight: bold; padding: 4px 8px; border-radius: 4px; }
    .status-HIGH { background-color: #f8d7da; color: #721c24; font-weight: bold; padding: 4px 8px; border-radius: 4px; }
    .param-col { font-family: monospace; font-size: 12px; color: #555; }
</style>
</head>
<body>
<h2>Fraud Detection Transaction Log (200 Examples)</h2>
<table>
    <thead>
        <tr>
            <th>Tx ID</th>
            <th>Amount</th>
            <th>Parameters (The "Truth")</th>
            <th>Trust Level</th>
            <th>Risk Score</th>
            <th>Status</th>
            <th>Explanation / Rule Violation</th>
        </tr>
    </thead>
    <tbody>
"""

trust_map = {0: "Stranger", 1: "Direct Friend", 2: "Friend of Friend"}

for t in transactions:
    trust_str = trust_map.get(t['trust'], "Unknown")
    
    params = (f"Time: {t['hour']}:00 | Velocity: {t['velocity']} | "
              f"Loop: {t['loop']} | Dormancy: {t['inactive']}d | "
              f"AvgAmt: {t['avg']} | AI: {t['ai']}")
              
    html += f"""
        <tr>
            <td>{t['id']}</td>
            <td><strong>₹{t['amount']}</strong></td>
            <td class="param-col">{params}</td>
            <td>{trust_str}</td>
            <td>{t['score']}</td>
            <td><span class="status-{t['status']}">{t['status']}</span></td>
            <td>{t['reason']}</td>
        </tr>
    """

html += """
    </tbody>
</table>
</body>
</html>
"""

with open("fraud_report.html", "w", encoding="utf-8") as f:
    f.write(html)

print("Generated fraud_report.html")
