import os
import sys
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from database import engine
from sqlalchemy import text

def run():
    print("Migrating DB...")
    with engine.connect() as con:
        try:
            con.execute(text("ALTER TABLE users ADD COLUMN summary_frequency INTEGER DEFAULT 1;"))
            con.commit()
        except Exception as e:
            print(f"Error adding summary_frequency: {e}")
            
        try:
            con.execute(text("ALTER TABLE users ADD COLUMN last_summary_sent_at TIMESTAMP;"))
            con.commit()
        except Exception as e:
            print(f"Error adding last_summary_sent_at: {e}")
            
        try:
            con.execute(text("ALTER TABLE users ADD COLUMN spending_limit FLOAT;"))
            con.commit()
        except Exception as e:
            print(f"Error adding spending_limit: {e}")
            
        try:
            con.execute(text("ALTER TABLE users ADD COLUMN spending_limit_period INTEGER DEFAULT 1;"))
            con.commit()
        except Exception as e:
            print(f"Error adding spending_limit_period: {e}")
            
        try:
            con.execute(text("ALTER TABLE users ADD COLUMN spending_limit_updated_at TIMESTAMP;"))
            con.commit()
        except Exception as e:
            print(f"Error adding spending_limit_updated_at: {e}")

if __name__ == "__main__":
    run()
