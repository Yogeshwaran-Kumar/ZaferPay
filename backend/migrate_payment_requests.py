import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    print("Error: DATABASE_URL not found in .env")
    exit(1)

# Connect to the database
engine = create_engine(DATABASE_URL)

def migrate():
    try:
        with engine.connect() as connection:
            print("Connected to database. Checking for missing columns...")
            
            # Use raw SQL to add columns if they don't exist
            # PostgreSQL doesn't have IF NOT EXISTS for ADD COLUMN in older versions, 
            # but we can check the information_schema
            
            check_sql = text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name='payment_requests' AND column_name='target_upi';
            """)
            result = connection.execute(check_sql).fetchone()
            
            if not result:
                print("Adding target_upi column...")
                connection.execute(text("ALTER TABLE payment_requests ADD COLUMN target_upi VARCHAR;"))
                print("Added target_upi.")
            else:
                print("target_upi already exists.")
                
            check_sql = text("""
                SELECT column_name 
                FROM information_schema.columns 
                WHERE table_name='payment_requests' AND column_name='circle_id';
            """)
            result = connection.execute(check_sql).fetchone()
                
            if not result:
                print("Adding circle_id column...")
                connection.execute(text("ALTER TABLE payment_requests ADD COLUMN circle_id INTEGER REFERENCES upi_circles(id);"))
                print("Added circle_id with foreign key.")
            else:
                print("circle_id already exists.")
            
            connection.commit()
            print("Migration completed successfully.")
            
    except Exception as e:
        print(f"Migration failed: {e}")

if __name__ == "__main__":
    migrate()
