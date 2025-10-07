# BNPB

BNPB is a personal relationship manager built with Flutter. It keeps contact
context, reminders, prayer requests, and interaction history completely offline
while offering analytics and export tooling.

## Security & privacy

- Contact data is stored in an encrypted SQLCipher database. The encryption key
  is generated on-device and saved via the platform key store.
- Optional passcode and biometric gating prevents casual access to the app. The
  lock screen appears on launch whenever a passcode is configured.
- CSV, PDF, and encrypted archive exports allow selective field inclusion. AES
  encrypted archives require a user-supplied passphrase.
- A “Securely purge all data” action overwrites and deletes the encrypted
  database, clears backups, removes credentials, and cancels notifications.
- See the [Privacy Policy & Personal Usage Guidelines](docs/privacy_policy.md)
  for a detailed breakdown of how the app handles sensitive information.

## Documentation

- [Privacy Policy & Personal Usage Guidelines](docs/privacy_policy.md)
- [Optional facial recognition pipeline research](docs/facial_recognition_pipeline.md)

## Development

Run the usual Flutter commands during development:

```bash
flutter pub get
flutter analyze
flutter test
```
