import firebase_admin
from firebase_admin import credentials, messaging
import os
from logging_config import logger

# Initialize Firebase Admin SDK
# You need to download the service account key from Firebase Console
# Project Settings -> Service Accounts -> Generate New Private Key
# Save it as 'firebase_credentials.json' in the backend folder

# Use absolute path so it works regardless of working directory
CREDENTIALS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "firebase_credentials.json")

_is_initialized = False

def initialize_firebase():
    global _is_initialized
    if _is_initialized:
        return True

    if not os.path.exists(CREDENTIALS_PATH):
        logger.warning(f"Firebase credentials not found at {CREDENTIALS_PATH}. Push notifications will be disabled.")
        return False

    try:
        cred = credentials.Certificate(CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        _is_initialized = True
        logger.info("Firebase Admin SDK initialized successfully.")
        return True
    except ValueError as e:
        # Already initialized (e.g., by another module or hot-reload)
        if "already exists" in str(e):
            _is_initialized = True
            logger.info("Firebase Admin SDK was already initialized.")
            return True
        logger.error(f"Failed to initialize Firebase: {e}")
        return False
    except Exception as e:
        logger.error(f"Failed to initialize Firebase: {e}")
        return False

# Eagerly initialize Firebase when this module is imported
initialize_firebase()

def send_fcm_notification(token: str, title: str, body: str, data: dict = None):
    """
    Send a push notification to a specific device using FCM.
    """
    if not _is_initialized:
        initialize_firebase()
        if not _is_initialized:
            logger.warning("Skipping notification: Firebase not initialized.")
            return False

    if not token:
        logger.warning(f"Skipping notification '{title}': No FCM token provided.")
        return False

    try:
        # Convert all data values to strings (FCM requirement)
        str_data = {k: str(v) for k, v in data.items()} if data else {}

        message = messaging.Message(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data=str_data,
            token=token,
            # Add Android-specific config for high priority delivery
            android=messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    channel_id='high_importance_channel_v2',
                    priority='max',
                    default_sound=True,
                    default_vibrate_timings=True,
                ),
            ),
        )

        response = messaging.send(message)
        logger.info(f"FCM notification sent successfully: {response} | title='{title}' | token_prefix='{token[:20]}...'")
        return True
    except messaging.UnregisteredError:
        logger.warning(f"FCM token is no longer valid (unregistered). title='{title}' | token_prefix='{token[:20]}...'")
        return False
    except messaging.SenderIdMismatchError:
        logger.error(f"FCM SenderIdMismatch - credentials don't match app's Firebase project. title='{title}'")
        return False
    except Exception as e:
        logger.error(f"Error sending FCM notification: {e} | title='{title}' | token_prefix='{token[:20] if token else 'None'}...'")
        return False

import models

def send_push_notification(db, user_id: int, title: str, message: str, notif_type: str = "info", background_tasks=None):
    """
    Saves a notification to the database and attempts to send a FCM push if configured.
    Uses db.flush() instead of db.commit() so the notification is committed
    together with the caller's transaction.
    """
    try:
        new_notif = models.Notification(
            user_id=user_id,
            title=title,
            message=message,
            type=notif_type
        )
        db.add(new_notif)
        db.flush()  # Write to DB but let the caller commit
        
        logger.info(f"Notification saved for user {user_id}: {title} - {message}")
        
        # Look up user's FCM token and send push notification
        user = db.query(models.User).filter(models.User.id == user_id).first()
        if user and user.fcm_token:
            logger.info(f"Sending FCM push to user {user_id} (token_prefix='{user.fcm_token[:20]}...')")
            if background_tasks:
                background_tasks.add_task(
                    send_fcm_notification,
                    token=user.fcm_token,
                    title=title,
                    body=message,
                    data={"type": notif_type}
                )
            else:
                # If no background_tasks provided, run synchronously
                send_fcm_notification(
                    token=user.fcm_token,
                    title=title,
                    body=message,
                    data={"type": notif_type}
                )
        else:
            if not user:
                logger.warning(f"Cannot send FCM push: User {user_id} not found in database.")
            else:
                logger.warning(f"Cannot send FCM push: User {user_id} ({user.username}) has no FCM token stored.")
                
        return True
    except Exception as e:
        logger.error(f"Error saving push notification: {e}")
        # Do NOT rollback here — the caller controls the transaction
        return False


