
import random
from datetime import datetime, timedelta

# Constants
RISK_THRESHOLD_HIGH = 80
RISK_THRESHOLD_WARN = 50

transactions = []
trust_depth_map = {0: "Stranger", 1: "Direct Friend", 2: "Friend of Friend"}

def generate_transaction(i, force_all_rules=False):
    # Randomize inputs
    tx_id = f"TXN{100000+i}"
    
    # Defaults
    trust_depth = random.choice([0, 1, 2])
    amount = round(random.uniform(50, 10000), 2)
    hour = random.randint(0, 23)
    recent_txns = random.randint(0, 8)
    is_loop = random.choice([True, False])
    days_inactive = random.randint(0, 60)
    avg_amount = round(random.uniform(100, 1000), 2)
    ai_score = round(random.uniform(-0.6, 0.6), 2)

    # If "force_all_rules" is True, we construct the ULTIMATE BAD TRANSACTION
    # that triggers EVERY possible negative rule simultaneously.
    if force_all_rules:
        amount = 15000.00         # >5000 (F7) & >3x Avg (F5) & >2000 (F8)
        avg_amount = 100.00       # Low avg to ensure spike
        trust_depth = 0           # Stranger (F12)
        hour = 4                  # Night Owl 3-5AM (F9)
        ai_score = -0.5           # Anomaly (F4)
        is_loop = True            # Circular (F2)
        days_inactive = 45        # Dormant >30 (F3)
        recent_txns = 6           # Velocity >5 (F1)
        
    # --- LOGIC APPLICATION (Mirroring fraud_engine.py EXACTLY) ---
    risk_score = 0
    # We collect ALL violations, even if we would technically "return early" in code
    # This gives the "Total Truth" view the user requested.
    violations = []
    
    # F1: Velocity
    if recent_txns >= 5:
        violations.append({"code": "F1_VELOCITY", "desc": "5+ Txns in 10m", "score": 100, "action": "BLOCK"})
        risk_score += 100 

    # F2: Circular
    if is_loop:
        violations.append({"code": "F2_CIRCULAR", "desc": "A->B->A Loop Pattern", "score": 40, "action": "FLAG"})
        risk_score += 40
        
    # F3: Dormant
    if days_inactive > 30 and amount > 500:
        violations.append({"code": "F3_DORMANT_SPIKE", "desc": "Inactive >30d + High Amount", "score": 100, "action": "BLOCK"})
        risk_score += 100
    
    # F5: Ticket Spike
    if amount > (avg_amount * 3):
        violations.append({"code": "F5_AMOUNT_SPIKE", "desc": "Amount > 3x Historical Avg", "score": 50, "action": "FLAG"})
        risk_score += 50
        
    # F9: Night Owl
    if 3 <= hour <= 5:
        violations.append({"code": "F9_NIGHT_OWL", "desc": "Transaction at 3AM-5AM", "score": 25, "action": "FLAG"})
        risk_score += 25
        
    # STAGE 2: SOCIAL GRAPH
    if trust_depth == 1:
        # Friend Bonus
        risk_score -= 10
    elif trust_depth == 0: # Stranger
        violations.append({"code": "F12_STRANGER", "desc": "No Trust History (Depth 0)", "score": 20, "action": "FLAG"})
        risk_score += 20
        
        # F8: Stranger High Value
        if amount > 2000:
            violations.append({"code": "F8_STRANGER_HIGH_VAL", "desc": ">2000 to Stranger", "score": 30, "action": "FLAG"})
            risk_score += 30
            
        # F7: Untrusted Receiver High Value (Block)
        if amount > 5000:
             violations.append({"code": "F7_UNTRUSTED_BLOCK", "desc": ">5000 to Stranger", "score": 100, "action": "BLOCK"})
             risk_score += 100

    # STAGE 3: AI
    if ai_score < -0.2:
        violations.append({"code": "F4_AI_ANOMALY", "desc": "Isolation Forest Score < -0.2", "score": 65, "action": "FLAG"})
        risk_score += 65
    elif ai_score < 0:
        risk_score += 20
        
    # Final Calc (Uncapped for analysis, but capped for final status)
    # We keep 'risk_score' as the cumulative theoretical score for the "Truth" display
    
    display_score = max(0, min(100, risk_score))
    
    status = "SAFE"
    if display_score >= RISK_THRESHOLD_HIGH:
        status = "HIGH"
    elif display_score >= RISK_THRESHOLD_WARN:
        status = "WARN"
        
    # Determine PRIMARY reason (The one that would strictly block it first in real engine)
    # Order: F1 -> F3 -> F7 -> Score
    primary_blocker = ""
    for v in violations:
        if v['code'] == "F1_VELOCITY": primary_blocker = "F1 (Velocity)" ; break
    if not primary_blocker:
        for v in violations:
            if v['code'] == "F2_CIRCULAR": pass # not a blocker
            if v['code'] == "F3_DORMANT_SPIKE": primary_blocker = "F3 (Dormant)" ; break
    if not primary_blocker:
        for v in violations:
            if v['code'] == "F7_UNTRUSTED_BLOCK": primary_blocker = "F7 (Untrusted >5k)" ; break
            
    if not primary_blocker and status == "HIGH":
        primary_blocker = "Cumulative Score"

    return {
        "id": tx_id, "amount": amount, "hour": hour, "trust": trust_depth,
        "velocity": recent_txns, "loop": is_loop, "inactive": days_inactive,
        "avg": avg_amount, "ai": ai_score,
        "status": status, "violations": violations, "score": risk_score,
        "capped_score": display_score, "primary": primary_blocker
    }

# Generate 5 examples that hit EVERYTHING
for i in range(5):
    transactions.append(generate_transaction(i, force_all_rules=True))

# Generate 195 random ones
for i in range(5, 200):
   transactions.append(generate_transaction(i))

# Generate HTML
html = """<!DOCTYPE html>
<html>
<head>
<style>
    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #eaeff2; padding: 20px; color: #1a1a1a; }
    h2 { color: #2c3e50; }
    .card-container { display: flex; flex-direction: column; gap: 15px; }
    .transaction-card { 
        background: white; 
        border-radius: 8px; 
        box-shadow: 0 2px 5px rgba(0,0,0,0.05); 
        padding: 0; 
        overflow: hidden;
        border-left: 6px solid #ccc;
    }
    
    .card-header {
        padding: 15px 20px;
        display: flex;
        justify-content: space-between;
        align-items: center;
        background: #f8f9fa;
        border-bottom: 1px solid #eee;
    }
    
    .card-body {
        padding: 20px;
        display: flex;
        gap: 30px;
    }
    
    .params-box {
        flex: 1;
        font-family: 'Consolas', monospace;
        font-size: 13px;
        color: #444;
        background: #f1f3f5;
        padding: 15px;
        border-radius: 6px;
    }
    
    .violations-box {
        flex: 1.5;
    }
    
    .violation-tag {
        display: inline-block;
        padding: 4px 8px;
        margin: 2px;
        border-radius: 4px;
        font-size: 12px;
        font-weight: bold;
        background: #e9ecef;
        border: 1px solid #dee2e6;
        color: #495057;
    }
    
    /* Status Styles */
    .status-SAFE { border-left-color: #2e7d32; }
    .status-SAFE .card-header { background: #e8f5e9; }
    .status-SAFE .badge { background: #c8e6c9; color: #1b5e20; }
    
    .status-WARN { border-left-color: #f57f17; }
    .status-WARN .card-header { background: #fff8e1; }
    .status-WARN .badge { background: #ffe082; color: #f57f17; }
    
    .status-HIGH { border-left-color: #c62828; }
    .status-HIGH .card-header { background: #ffebee; }
    .status-HIGH .badge { background: #ffcdd2; color: #b71c1c; }
    
    .badge { padding: 5px 10px; border-radius: 12px; font-weight: bold; text-transform: uppercase; font-size: 12px; }
    
    .meta-label { font-size: 11px; color: #888; text-transform: uppercase; display: block; margin-bottom: 4px; }
    
    .violation-item {
        margin-bottom: 6px;
        padding-bottom: 6px;
        border-bottom: 1px dashed #eee;
        display: flex;
        justify-content: space-between;
    }
    
    .red-text { color: #d32f2f; font-weight: bold; }
    .orange-text { color: #f57c00; font-weight: bold; }
    
</style>
</head>
<body>
<h2>🚨 Fraud Detection "Deep Dive" Log</h2>
<p>Examples showing <strong>ALL</strong> internal violations, even those normally hidden by early blocking.</p>

<div class="card-container">
"""

for t in transactions:
    trust_str = trust_depth_map.get(t['trust'], "Unknown")
    
    # Violations HTML
    v_html = ""
    if not t['violations']:
        v_html = "<span style='color:green'>✔ No Rule Violations (Clean)</span>"
    else:
        for v in t['violations']:
            color_class = "red-text" if v['action'] == "BLOCK" else "orange-text"
            v_html += f"""
            <div class="violation-item">
                <span><span class="{color_class}">[{v['code']}]</span> {v['desc']}</span>
                <span style="font-size:11px; background:#eee; padding:2px 5px; border-radius:4px;">+{v['score']} Risk</span>
            </div>
            """
            
    # Params HTML
    p_html = f"""
    <div><strong>Time:</strong> {t['hour']}:00</div>
    <div><strong>Velocity:</strong> {t['velocity']}/10m</div>
    <div><strong>Loop:</strong> {t['loop']}</div>
    <div><strong>Dormant:</strong> {t['inactive']} days</div>
    <div><strong>Avg Amt:</strong> ₹{t['avg']}</div>
    <div><strong>AI Score:</strong> {t['ai']}</div>
    """

    count_violations = len(t['violations'])
    warning_text = f"{count_violations} Violation{'s' if count_violations != 1 else ''}"
    
    html += f"""
    <div class="transaction-card status-{t['status']}">
        <div class="card-header">
            <div>
                <strong>{t['id']}</strong> 
                <span style="margin-left:10px; font-size:18px;">₹{t['amount']}</span>
                <span style="margin-left:15px; font-size:12px; color:#555;">➡ {trust_str}</span>
            </div>
            <span class="badge">{t['status']} (Score: {t['capped_score']})</span>
        </div>
        <div class="card-body">
            <div class="params-box">
                <span class="meta-label">INPUT SIGNALS (Feature Vector)</span>
                {p_html}
            </div>
            <div class="violations-box">
                <span class="meta-label">INTERNAL LOGIC TRACE ({warning_text})</span>
                {v_html}
            </div>
        </div>
    </div>
    """

html += """
</div>
</body>
</html>
"""

with open("fraud_report_deep.html", "w", encoding="utf-8") as f:
    f.write(html)

print("Generated fraud_report_deep.html")
