import logging
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
import pytz

import models
import database
import notifications

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("daily_summary")

# Global scheduler instance
_scheduler = None

def get_db():
    db = database.SessionLocal()
    try:
        yield db
    finally:
        db.close()

def send_daily_summaries():
    """
    Calculates the daily summary for all users and sends a push notification.
    Runs daily at 10 PM.
    """
    logger.info("Starting daily summary calculations...")
    db_generator = get_db()
    db: Session = next(db_generator)

    try:
        # 1. Get all users who have an FCM token
        users = db.query(models.User).filter(models.User.fcm_token.isnot(None)).all()
        logger.info(f"Found {len(users)} users with FCM tokens.")

        # Time range: Last 24 hours
        end_time = datetime.now()
        start_time = end_time - timedelta(days=1)

        sent_count = 0

        for user in users:
            # 2. Calculate Receive Total
            received_sum = db.query(func.sum(models.Transaction.amount)).filter(
                models.Transaction.receiver_id == user.id,
                models.Transaction.status == "SUCCESS",
                models.Transaction.timestamp >= start_time,
                models.Transaction.timestamp <= end_time
            ).scalar()
            
            # 3. Calculate Send Total
            sent_sum = db.query(func.sum(models.Transaction.amount)).filter(
                models.Transaction.sender_id == user.id,
                models.Transaction.status == "SUCCESS",
                models.Transaction.timestamp >= start_time,
                models.Transaction.timestamp <= end_time
            ).scalar()

            received = received_sum or 0.0
            sent = sent_sum or 0.0

            # Only send if there was some activity
            if received > 0 or sent > 0:
                title = "📊 Your Daily Summary"
                body = f"Today's Activity: You received ₹{received:.2f} and spent ₹{sent:.2f}."
                
                # Send the notification
                success = notifications.send_fcm_notification(
                    token=user.fcm_token,
                    title=title,
                    body=body,
                    data={"type": "daily_summary"}
                )
                if success:
                    sent_count += 1
                    
        logger.info(f"Daily summaries sent successfully to {sent_count} users.")

    except Exception as e:
        logger.error(f"Error sending daily summaries: {e}")
    finally:
        # Important to close the DB session manually because we are out of FastAPI's request lifecycle
        try:
            db_generator.close()
        except:
             pass

def start_daily_summary_scheduler():
    global _scheduler
    if _scheduler and _scheduler.running:
        logger.warning("Daily summary scheduler is already running.")
        return

    # Use India Standard Time (IST) if needed, otherwise defaults to server time
    # User's time is +05:30 (IST), so better to explicitly use Asia/Kolkata
    ist_tz = pytz.timezone('Asia/Kolkata')
    _scheduler = BackgroundScheduler(timezone=ist_tz)
    
    # Schedule to run every day at 22:00 (10:00 PM)
    _scheduler.add_job(
        func=send_daily_summaries,
        trigger="cron",
        hour=22,
        minute=0,
        id="daily_summary_job",
        name="Send Daily Summaries to Users",
        replace_existing=True
    )
    
    _scheduler.start()
    logger.info("✅ Daily summary scheduler started (Runs at 10:00 PM IST daily).")

def stop_daily_summary_scheduler():
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown()
        _scheduler = None
        logger.info("🛑 Daily summary scheduler stopped.")
        
# Allow running standalone for debugging
if __name__ == "__main__":
    send_daily_summaries()
