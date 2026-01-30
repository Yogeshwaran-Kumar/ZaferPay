import database, models
import os

def init_db():
    if os.path.exists("transactions.db"):
        os.remove("transactions.db")
        print("Removed existing transactions.db")
    
    print("Creating new database...")
    models.Base.metadata.create_all(bind=database.engine)
    print("Database created.")
    
    # Run seed
    print("Database initialization complete (No seed data found).")

if __name__ == "__main__":
    init_db()
