import database
import models
from sqlalchemy import text

def apply_immutable_audit():
    print("--- Applying Immutable Audit Log (Military-Grade) ---")
    engine = database.engine
    
    try:
        with engine.connect() as conn:
            # 1. Drop old table (since schema changed from state-based to event-based)
            print("Resetting 'login_history' table to new event-based schema...")
            conn.execute(text("DROP TABLE IF EXISTS login_history CASCADE"))
            conn.commit()
            
            # 2. Recreate table using SQLAlchemy
            print("Recreating table...")
            models.Base.metadata.create_all(bind=engine)
            
            # 3. Create Immutability Trigger
            print("Adding SQL Immutability Trigger...")
            
            trigger_function = """
            CREATE OR REPLACE FUNCTION block_immutable_log_updates()
            RETURNS TRIGGER AS $$
            BEGIN
                RAISE EXCEPTION 'This table is immutable (Military-Grade). Updates and Deletions are forbidden.';
            END;
            $$ LANGUAGE plpgsql;
            """
            
            trigger_applied = """
            DROP TRIGGER IF EXISTS trg_immutable_login_history ON login_history;
            CREATE TRIGGER trg_immutable_login_history
            BEFORE UPDATE OR DELETE ON login_history
            FOR EACH ROW EXECUTE FUNCTION block_immutable_log_updates();
            """
            
            conn.execute(text(trigger_function))
            conn.execute(text(trigger_applied))
            conn.commit()
            
            print("✅ Immutable Audit Log applied and locked successfully.")
            
    except Exception as e:
        print(f"❌ Error applying immutability: {e}")

if __name__ == "__main__":
    apply_immutable_audit()
