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

        end_time = datetime.now()
        sent_count = 0

        for user_item in users:
            # 1.1 Use pessimistic locking to ensure only one worker processes this user
            # We must re-fetch the user within a transaction to apply the lock correctly
            user = db.query(models.User).with_for_update().filter(models.User.id == user_item.id).first()
            if not user:
                continue

            # Check summary frequency logic
            frequency_days = user.summary_frequency or 1
            last_sent = user.last_summary_sent_at
            
            # Use total seconds for more precise frequency check (within a 1-hour window tolerance)
            # This prevents duplicate triggers if multiple workers start within a few minutes of each other.
            if last_sent:
                diff_seconds = (end_time - last_sent).total_seconds()
                # If we've already sent a summary within the frequency window (minus 1 hour buffer)
                if diff_seconds < (frequency_days * 86400 - 3600):
                    continue
                
            start_time = end_time - timedelta(days=frequency_days)
        
            # 2. Calculate Receive Total
            received_sum = db.query(func.sum(models.Transaction.amount)).filter(
                models.Transaction.receiver_id == user.id,
                models.Transaction.status == "SUCCESS",
                models.Transaction.timestamp >= start_time,
                models.Transaction.timestamp <= end_time
            ).scalar()
            
            # 3. Calculate Send Total
            sent_sum = db.query(func.sum(models.Transaction.amount)).filter(
                (models.Transaction.sender_id == user.id) | (models.Transaction.initiated_by_id == user.id),
                models.Transaction.status == "SUCCESS",
                models.Transaction.timestamp >= start_time,
                models.Transaction.timestamp <= end_time
            ).scalar()

            # 4. Calculate Breakdown for Message
            self_sent_sum = db.query(func.sum(models.Transaction.amount)).filter(
                models.Transaction.sender_id == user.id,
                (models.Transaction.initiated_by_id == None) | (models.Transaction.initiated_by_id == user.id),
                models.Transaction.status == "SUCCESS",
                models.Transaction.timestamp >= start_time,
                models.Transaction.timestamp <= end_time
            ).scalar()

            # ... Calculate other sums ...
            circle_sent_sum = db.query(func.sum(models.Transaction.amount)).filter(
                (
                    (models.Transaction.sender_id == user.id) & (models.Transaction.initiated_by_id != None) & (models.Transaction.initiated_by_id != user.id)
                ) | (
                    (models.Transaction.initiated_by_id == user.id) & (models.Transaction.sender_id != user.id)
                ),
                models.Transaction.status == "SUCCESS",
                models.Transaction.timestamp >= start_time,
                models.Transaction.timestamp <= end_time
            ).scalar()

            received = received_sum or 0.0
            sent = sent_sum or 0.0
            circle_sent = circle_sent_sum or 0.0

            # Only send if there was some activity
            if received > 0 or sent > 0:
                period_str = "Daily" if frequency_days == 1 else f"{frequency_days}-Day"
                if frequency_days == 7: period_str = "Weekly"
                if frequency_days == 30: period_str = "Monthly"
                
                title = f"Your {period_str} Summary"
                body = f"Activity: You received ₹{received:.2f} and spent ₹{sent:.2f}."
                if circle_sent > 0:
                    if user.bank_name: # Parent
                        body += f" (Inc. ₹{circle_sent:.2f} via UPI Circle by members)"
                    else: # Child/Member
                        body += f" (Inc. ₹{circle_sent:.2f} via UPI Circle by you)"
                
                # Send the notification
                success = notifications.send_fcm_notification(
                    token=user.fcm_token,
                    title=title,
                    body=body,
                    data={"type": "daily_summary"}
                )
                if success:
                    sent_count += 1
                    user.last_summary_sent_at = end_time
                    db.commit() # Commit immediately to release the lock for this user
            else:
                # Still update the timestamp even if no activity, so we don't keep re-checking
                user.last_summary_sent_at = end_time
                db.commit()
                    
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
