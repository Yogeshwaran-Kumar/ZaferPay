import sqlite3
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "transactions.db")
OUTPUT_FILE = os.path.join(BASE_DIR, "db_output.txt")

def show_table(cursor, f, table_name):
    try:
        cursor.execute(f"SELECT * FROM {table_name}")
        rows = cursor.fetchall()
        
        f.write(f"\n--- Data for table: {table_name} ---\n")
        if not rows:
            f.write("No data found.\n")
            return

        columns = [description[0] for description in cursor.description]
            
        # Simple pretty print
        # Calculate column widths
        widths = [len(c) for c in columns]
        for row in rows:
            for i, val in enumerate(row):
                widths[i] = max(widths[i], len(str(val)))
        
        # Print header
        header = " | ".join(f"{col:<{widths[i]}}" for i, col in enumerate(columns))
        f.write(header + "\n")
        f.write("-" * len(header) + "\n")
        
        # Print rows
        for row in rows:
            formatted_row = []
            for i, val in enumerate(row):
                formatted_row.append(f"{str(val):<{widths[i]}}")
            f.write(" | ".join(formatted_row) + "\n")
                
    except sqlite3.OperationalError as e:
        f.write(f"Error reading {table_name}: {e}\n")

if __name__ == "__main__":
    if not os.path.exists(DB_PATH):
        print(f"Database file not found at {DB_PATH}")
        exit(1)
    
    print(f"Writing database dump to: {os.path.abspath(OUTPUT_FILE)}")
    
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        tables = ["users", "transactions", "sender_profiles", "receiver_profiles"]
        for t in tables:
            show_table(cursor, f, t)
            
    conn.close()
    print("Done.")
