import sqlite3

conn = sqlite3.connect('hastane_v2.db')
cursor = conn.cursor()

tables = cursor.execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','view')").fetchall()
print("TABLES AND VIEWS:")
for t, tp in tables:
    cols = [c[1] for c in cursor.execute(f"PRAGMA table_info({t})")]
    print(f"{tp.upper()} {t}: {cols}")
