/// Privacy policy and personal usage guidance displayed inside the app.
const String kPrivacyPolicyText = '''
BNPB Privacy Policy & Personal Usage Guidelines

Last updated: February 2026

Overview
BNPB is designed with a "local-first" philosophy. Your contact insights, 
interaction history, and personal reflections are stored and processed entirely 
on your device. No data is uploaded to remote servers for processing, and the 
developers have no access to your information.

Data storage & encryption
• All contact details, interaction history, prayer requests, and notification
  preferences are written to an encrypted SQLCipher database.
• The encryption key is generated locally and saved in the device key store via
  Flutter Secure Storage (e.g., Keychain on iOS/macOS, Keystore on Android). 
  This key never leaves your device.
• On-device analytics (such as time investment charts and interaction gaps) are 
  calculated locally from your encrypted data. No usage metrics are transmitted 
  to any external service.

Sync & Backups
BNPB provides options to keep your data safe across devices:
• Local Sync: You may choose a folder on your device (or a shared cloud folder 
  like iCloud, OneDrive, or Dropbox) to store a backup. Only the encrypted 
  database file is copied.
• Google Drive Sync: If enabled, BNPB uses Google Drive to sync your encrypted 
  database. This uses the "App Data Folder" scope, meaning the files are 
  invisible to you in the standard Drive interface and are only accessible by 
  BNPB. 
• Google Identity: When signing in for Google Drive sync, BNPB only uses your 
  identity to facilitate the connection to your storage. We do not store your 
  profile information or track your Google account activity.

On-device AI features (opt-in)
• AI suggestions: When the "AI features" toggle in Settings is enabled, BNPB
  downloads a Gemma language model and runs inference on your device. Prompts
  and responses never leave the device. The follow-up suggestion path sends
  only the just-saved interaction's fields to the model. The interaction
  summary card and the outreach "Suggest opener" feature feed a wider slice
  — the focal contact's last 5–10 interactions plus active prayer requests
  — to generate their output. No participant ids, no other-contact names,
  and no data from contacts other than the one being viewed are included in
  any AI prompt.
• Ask search (semantic): When you download the Gecko embedder from AI
  Settings, BNPB builds a local vector index of your interactions and
  prayer requests so the search bar's "Ask" toggle can answer
  intent-shaped questions. The embedder runs entirely on this device and
  the vector index is stored next to the encrypted database in the app's
  private support directory. Queries are embedded on device; no text is
  sent to a server. The index is cleared automatically on import and can
  be removed any time by deleting the embedder from AI Settings.

Permissions & Notifications
• Notifications: Reminders for follow-ups and prayer updates are managed by the 
  operating system's local notification service.
• Precise Scheduling (Android): On Android 12+, we may request the "Exact Alarm" 
  permission. This is used solely to ensure your reminders fire at the precise 
  minute requested, rather than being delayed by system battery-saving measures.
• Biometrics: If enabled, BNPB uses system-level biometric prompts (Face ID,
  Touch ID, or Android Biometric) to unlock the app. The app never sees or
  stores your biometric data.

Exports
• CSV, PDF, and JSON exports are created on demand and stay local until you 
  explicitly share or move them.
• Encrypted archives (.zip) use AES-256 encryption to protect exported data. 
  You are responsible for the security of the passphrase used for these files.

Deletion & retention
• The “Securely purge all data” action in Settings overwrites the encrypted 
  database, removes local backups, clears encryption keys, and cancels all 
  scheduled notifications.
• Deleting a contact removes all associated history and reminders from the 
  local database immediately.

Personal usage guidelines
• Responsibility: You are responsible for the data you collect. Ensure you 
  respect the privacy and consent of the individuals in your address book.
• Non-Commercial: BNPB is a personal tool. Do not sell or commercialize the 
  personal data of others stored within the app.
• Compliance: Follow local regulations (such as GDPR or CCPA) regarding 
  personal data management and the storage of sensitive information.

Questions & changes
BNPB is a proprietary tool and its source code is not publicly available. 
Please report any security concerns or policy gaps through the official 
support channels.
''';
