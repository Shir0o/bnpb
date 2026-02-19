import re

with open('lib/db/db_helper.dart', 'r') as f:
    content = f.read()

# Pattern matches the bad line, flexible on quotes
pattern = r"await db\.execute\(['\"].*ALTER TABLE prayer_lists ADD COLUMN updatedAt.*['\"]\);"

match = re.search(pattern, content)
if match:
    correct = "await db.execute(\"ALTER TABLE prayer_lists ADD COLUMN updatedAt TEXT NOT NULL DEFAULT (datetime('now'))\");"
    content = content.replace(match.group(0), correct)
    with open('lib/db/db_helper.dart', 'w') as f:
        f.write(content)
    print("Fixed.")
else:
    print("Could not find line.")
