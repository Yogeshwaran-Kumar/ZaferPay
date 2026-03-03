import io
from fpdf import FPDF
from datetime import datetime
import os
from sqlalchemy.orm import Session
from database import SessionLocal
import models
import security
from logging_config import logger

class BankReportPDF(FPDF):
    def header(self):
        self.set_font('Arial', 'B', 15)
        self.cell(0, 10, 'Suspicious Transaction Activity Report', 0, 1, 'C')
        self.ln(5)

    def footer(self):
        self.set_y(-15)
        self.set_font('Arial', 'I', 8)
        self.cell(0, 10, f'Page {self.page_no()} - Generated on {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}', 0, 0, 'C')

def generate_bank_report_pdf(user: models.User, transactions: list):
    """
    Generates a PDF report of suspicious transactions in memory.
    Returns: BytesIO object containing the PDF data.
    """
    pdf = BankReportPDF()
    pdf.add_page()
    
    # User Details
    pdf.set_font('Arial', 'B', 12)
    pdf.cell(0, 10, 'User Details:', 0, 1)
    pdf.set_font('Arial', '', 11)
    pdf.cell(0, 8, f'Username: {user.username}', 0, 1)
    pdf.cell(0, 8, f'UPI ID: {user.upi_id}', 0, 1)
    pdf.cell(0, 8, f'Mobile (Hashed): {user.mobile_hash}', 0, 1)
    pdf.ln(10)
    
    # Transaction Details Table Header
    pdf.set_font('Arial', 'B', 10)
    pdf.cell(40, 10, 'ID', 1)
    pdf.cell(60, 10, 'Timestamp', 1)
    pdf.cell(30, 10, 'Amount (INR)', 1)
    pdf.cell(30, 10, 'Risk Score', 1)
    pdf.cell(30, 10, 'Status', 1)
    pdf.ln()
    
    # Transaction Rows
    pdf.set_font('Arial', '', 9)
    for tx in transactions:
        pdf.cell(40, 10, str(tx.transaction_id), 1)
        pdf.cell(60, 10, tx.timestamp.strftime("%Y-%m-%d %H:%M:%S"), 1)
        pdf.cell(30, 10, f'Rs. {tx.amount:.2f}', 1)
        pdf.cell(30, 10, str(tx.risk_score), 1)
        pdf.cell(30, 10, str(tx.status), 1)
        pdf.ln()

    # Get PDF as bytes in memory using a buffer
    buffer = io.BytesIO()
    pdf.output(buffer)
    buffer.seek(0)
    return buffer

def send_automated_bank_report(user_id: int):
    """
    Background task: Generates and "sends" a report to the bank.
    In a real scenario, this would use SMTP or an API.
    """
    db = SessionLocal()
    try:
        user = db.query(models.User).filter(models.User.id == user_id).first()
        if not user:
            logger.error(f"Reporting failed: User {user_id} not found.")
            return

        # Fetch recent risky transactions (last 24h)
        from datetime import timedelta
        day_ago = datetime.now() - timedelta(hours=24)
        risky_txs = db.query(models.Transaction).filter(
            models.Transaction.sender_id == user_id,
            models.Transaction.status == "SUCCESS",
            models.Transaction.risk_score.in_(["WARN", "HIGH"]),
            models.Transaction.timestamp >= day_ago
        ).order_by(models.Transaction.timestamp.desc()).all()

        if not risky_txs:
            logger.info(f"No risky transactions found for user {user_id} in the last 24h.")
            return

        # Generate PDF in memory
        pdf_buffer = generate_bank_report_pdf(user, risky_txs)
        
        # Simulated "Send" to Bank
        bank_email = os.getenv("BANK_REPORT_EMAIL", "fraud-alerts@bank-partner.com")
        logger.info(f"🚨 AUTOMATED BANK REPORT TRIGGERED for user {user.username} ({user_id})")
        logger.info(f"📤 Report (PDF Size: {len(pdf_buffer.getvalue())} bytes) simulated sent to {bank_email}")
        
    except Exception as e:
        logger.error(f"Error in automated bank reporting: {e}")
    finally:
        db.close()
