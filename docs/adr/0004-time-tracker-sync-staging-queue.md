# Sync Simple Time Tracker records via Google Drive with Staging Queue

We integrate Simple Time Tracker (STT) automated daily CSV exports into BNPB by querying the user's Google Drive `"Time Track"` folder using `drive.readonly` scope, parsing records tagged with `"Contact"`, and surfacing them in an Import Staging Queue with interactive dry-run review. We chose this over direct background writing or local file picking because Simple Time Tracker exports to Google Drive automatically at midnight, and user review preserves relationship data integrity without accidental duplicates or incorrect contact associations.

- Status: accepted
- Date: 2026-09-16
