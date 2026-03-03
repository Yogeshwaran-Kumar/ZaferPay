import firebase_admin
from firebase_admin import credentials, messaging
import os
from logging_config import logger

# Initialize Firebase Admin SDK
# You need to download the service account key from Firebase Console
# Project Settings -> Service Accounts -> Generate New Private Key
# Save it as 'firebase_credentials.json' in the backend folder
CREDENTIALS_PATH = "firebase_credentials.json"

_is_initialized = False

def initialize_firebase():
    global _is_initialized
    if _is_initialized:
        return

    if not os.path.exists(CREDENTIALS_PATH):
        logger.warning(f"⚠️ Firebase credentials not found at {CREDENTIALS_PATH}. Push notifications will be disabled.")
        return

    try:
        cred = credentials.Certificate(CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred)
        _is_initialized = True
        logger.info("✅ Firebase Admin SDK initialized successfully.")
    except Exception as e:
        logger.error(f"❌ Failed to initialize Firebase: {e}")

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
        )

        response = messaging.send(message)
        logger.info(f"📲 Notification sent successfully: {response}")
        return True
    except Exception as e:
        logger.error(f"❌ Error sending notification: {e}")
        return False
