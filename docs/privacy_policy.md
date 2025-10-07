# BNPB Privacy Policy & Personal Usage Guidelines

**Last updated:** May 2024

## Overview
BNPB stores contact insights entirely on your device. No data is uploaded to remote servers or shared with the developers. You control when information is exported, backed up, or deleted.

## Data storage & encryption
- All contact details, interaction history, prayer requests, and notification preferences are written to an encrypted SQLCipher database.
- The encryption key is generated locally and saved in the device key store via Flutter Secure Storage. The key never leaves your device.
- Automatic on-device backups reuse the same encryption, so copied database files remain protected unless you unlock the app.

## Local authentication
- You can enable a passcode to gate the app. Without the code, data cannot be viewed.
- Supported devices may also unlock with biometrics (Face ID, Touch ID, or fingerprint). Biometrics rely on the operating system—BNPB never sees your biometric template.

## Exports
- CSV and PDF exports are created on demand and stay local until you share them.
- Encrypted archives wrap selected contact fields in an AES-256 encrypted ZIP file that requires a passphrase to open.
- Exports should be shared only with people who have consent from the contacts represented in the file.

## Deletion & retention
- The “Securely purge all data” action overwrites the encrypted database, deletes rolling backups, clears encryption keys, and cancels notifications.
- You can also delete individual contacts at any time; associated reminders and history are removed alongside the record.

## Personal usage guidelines
- Collect information that contacts would reasonably expect you to remember and respect their privacy boundaries.
- Do not sell, publish, or otherwise commercialize personal data stored in BNPB without explicit permission from the individuals represented.
- Follow local regulations around personal data, consent, and biometric usage in your jurisdiction.

## Questions & changes
This project is open source. Review the repository documentation for update history and submit issues or pull requests if you notice gaps in the policy.
