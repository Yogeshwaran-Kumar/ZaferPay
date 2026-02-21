"""
Logging Configuration for Safe Pay Backend

Provides structured, leveled logging instead of print statements.
Logs to both console and file.
"""

import logging
import logging.handlers
import os
from datetime import datetime

# Create logs directory if it doesn't exist
LOG_DIR = os.path.join(os.path.dirname(__file__), 'logs')
os.makedirs(LOG_DIR, exist_ok=True)

# Log file with date
LOG_FILE = os.path.join(LOG_DIR, f'safepay_{datetime.now().strftime("%Y%m%d")}.log')


def setup_logging(level: str = "INFO") -> logging.Logger:
    """
    Configure and return the main application logger.
    
    Args:
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    
    Returns:
        Configured logger instance
    """
    # Create logger
    logger = logging.getLogger("safepay")
    logger.setLevel(getattr(logging, level.upper(), logging.INFO))
    
    # Prevent duplicate handlers
    if logger.handlers:
        return logger
    
    # Console Handler (colored output for development)
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.DEBUG)
    console_format = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(message)s',
        datefmt='%H:%M:%S'
    )
    console_handler.setFormatter(console_format)
    
    # File Handler (detailed for production/debugging)
    file_handler = logging.handlers.RotatingFileHandler(
        LOG_FILE,
        maxBytes=10*1024*1024,  # 10MB
        backupCount=5,
        encoding='utf-8'
    )
    file_handler.setLevel(logging.DEBUG)
    file_format = logging.Formatter(
        '%(asctime)s | %(levelname)-8s | %(name)s:%(lineno)d | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(file_format)
    
    # Add handlers
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    
    return logger


# Create the main logger instance
logger = setup_logging(os.getenv("LOG_LEVEL", "INFO"))


# Convenience functions for structured logging
def log_fraud_check(sender: str, receiver: str, amount: float, risk_label: str, 
                    ai_score: float, trust_depth: int, violations: list):
    """Log fraud evaluation result with structured data"""
    logger.info(
        f"FRAUD_EVAL | {sender} → {receiver} | ₹{amount:.2f} | "
        f"Risk={risk_label} | AI={ai_score:.3f} | Trust={trust_depth} | "
        f"Violations={violations}"
    )


def log_transaction(tx_id: str, sender: str, receiver: str, amount: float, status: str):
    """Log transaction completion"""
    if status == "SUCCESS":
        logger.info(f"TXN_SUCCESS | {tx_id} | {sender} → {receiver} | ₹{amount:.2f}")
    elif status == "BLOCKED":
        logger.warning(f"TXN_BLOCKED | {tx_id} | {sender} → {receiver} | ₹{amount:.2f}")
    else:
        logger.error(f"TXN_FAILED | {tx_id} | {sender} → {receiver} | ₹{amount:.2f}")


def log_login(username: str, device_hash: str, success: bool, reason: str = None):
    """Log login attempt"""
    if success:
        logger.info(f"LOGIN_OK | {username} | Device={device_hash[:8]}...")
    else:
        logger.warning(f"LOGIN_FAIL | {username} | Reason={reason}")


def log_security_event(event_type: str, user: str, details: str):
    """Log security-related events"""
    logger.warning(f"SECURITY | {event_type} | User={user} | {details}")


def log_error(context: str, error: Exception, user: str = None):
    """Log errors with full traceback"""
    user_str = f" | User={user}" if user else ""
    logger.error(f"ERROR | {context}{user_str} | {str(error)}", exc_info=True)
