# BNPB Privacy Policy & Personal Usage Guidelines

**Last updated:** February 2026

## Overview
BNPB is designed with a "local-first" philosophy. Your contact insights, 
interaction history, and personal reflections are stored and processed entirely 
on your device. No data is uploaded to remote servers for processing, and the 
developers have no access to your information.

## Data storage & encryption
- All contact details, interaction history, prayer requests, and notification
  preferences are written to an encrypted SQLCipher database.
- The encryption key is generated locally and saved in the device key store via
  Flutter Secure Storage (e.g., Keychain on iOS/macOS, Keystore on Android). 
  This key never leaves your device.
- On-device analytics (such as time investment charts and interaction gaps) are 
  calculated locally from your encrypted data. No usage metrics are transmitted 
  to any external service.

## Sync & Backups
BNPB provides options to keep your data safe across devices:
- **Local Sync:** You may choose a folder on your device (or a shared cloud folder 
  like iCloud, OneDrive, or Dropbox) to store a backup. Only the encrypted 
  database file is copied.
- **Google Drive Sync:** If enabled, BNPB uses Google Drive to sync your encrypted 
  database. This uses the "App Data Folder" scope, meaning the files are 
  invisible to you in the standard Drive interface and are only accessible by 
  BNPB. 
- **Google Identity:** When signing in for Google Drive sync, BNPB only uses your 
  identity to facilitate the connection to your storage. We do not store your 
  profile information or track your Google account activity.

## Permissions & Notifications
- **Notifications:** Reminders for follow-ups and prayer updates are managed by the 
  operating system's local notification service.
- **Precise Scheduling (Android):** On Android 12+, we may request the "Exact Alarm" 
  permission. This is used solely to ensure your reminders fire at the precise 
  minute requested, rather than being delayed by system battery-saving measures.
- **Biometrics:** If enabled, BNPB uses system-level biometric prompts (Face ID, 
  Touch ID, or Android Biometric) to unlock the app. The app never sees or 
  stores your biometric data.

## Exports
- CSV, PDF, and JSON exports are created on demand and stay local until you 
  explicitly share or move them.
- **Encrypted archives (.zip)** use AES-256 encryption to protect exported data. 
  You are responsible for the security of the passphrase used for these files.

## AI features (optional)
BNPB includes optional AI-assisted features (such as suggested follow-up
actions after logging an interaction, and tag suggestions for notes). AI
is off by default; when enabled, it runs on this device by default and
only sends note text off-device if you explicitly turn on the cloud
backend.

### On-device backend (default)
- **Off by default.** AI features are disabled until you explicitly enable
  them in Settings.
- **Model storage.** Enabling AI downloads a Gemma model file (Google's
  open-weight on-device LLM, ~3 GB) from Hugging Face over HTTPS. Because
  the Gemma repository is gated by Google, you must supply your own
  Hugging Face access token, which is stored in the device key store and
  is only sent in the Authorization header to huggingface.co during
  download. The model file is stored in the app's private support
  directory and can be removed from the AI settings screen at any time.
- **No data leaves the device while this backend is selected.** Inference
  runs locally. The model is given only the contents of the interaction
  or note you are working on (summary, medium, free-text notes); it does
  not receive your contact list, history, or any data from other contacts.
- **Outputs are suggestions only.** Generated tags or follow-up suggestions
  are not stored unless you tap to accept them, in which case the result is
  written to your local encrypted database the same way a manual entry
  would be.
- **No telemetry.** Prompts and model outputs are not transmitted to any
  server and are not logged outside the in-memory call.

### Cloud backend (opt-in, off by default)
A separate, explicitly opt-in cloud backend routes AI requests to Google's
Gemini API. It is off by default and requires both a deliberate toggle in
AI Settings and an API key you supply yourself.

- **Default off, explicit consent.** Turning the cloud backend on shows a
  disclosure dialog describing exactly what is sent and to where. Closing
  the dialog or choosing "Keep on-device" leaves AI on the local backend.
- **Bring your own key.** You generate a free Google AI Studio API key
  yourself and paste it into AI Settings. The key is stored in this
  device's secure key store (Keychain on iOS/macOS, Keystore on Android)
  and is only sent in the Authorization header to
  `generativelanguage.googleapis.com`. BNPB does not run a server, has no
  account with Google on your behalf, and never sees your key.
- **What is sent.** When the cloud backend is active, every AI request
  sends the text BNPB would have given to the local model (the note,
  interaction summary, or prayer-request text you asked the AI to
  process) to Google's Gemini API over HTTPS. Your contact list,
  unrelated interactions, vector index, and database key are never
  transmitted.
- **Governed by Google's terms.** Data sent to the Gemini API is
  processed under Google's API terms of service and privacy policy in
  addition to this one.
- **No silent fallback.** If the network is unreachable or Google rejects
  the request, the affected AI feature shows a visible error. BNPB will
  not run the same prompt on the local model behind your back —
  switching backends silently would obscure which path produced (or
  failed to produce) the result.
- **Reversible at any time.** You can switch the toggle back to
  on-device or clear the API key from AI Settings. Clearing the key
  removes it from the device key store immediately and disables the
  cloud backend on the next AI call.
- **Ask search (semantic).** Enabling the "Ask" toggle on the search bar
  requires a separate, smaller embedder model (Google Gecko 110M, ~110 MB)
  that you download from AI Settings. The embedder runs on this device and
  builds a local vector index of your interactions and prayer requests.
  The vector index is stored next to the encrypted database in the app's
  private support directory; query text is embedded on device and never
  transmitted. The index is cleared automatically when you import data and
  can be removed any time by deleting the embedder from AI Settings.

## Deletion & retention
- The “Securely purge all data” action in Settings overwrites the encrypted 
  database, removes local backups, clears encryption keys, deletes any 
  downloaded AI model file and Hugging Face token, and cancels all 
  scheduled notifications.
- Deleting a contact removes all associated history and reminders from the 
  local database immediately.

## Personal usage guidelines
- **Responsibility:** You are responsible for the data you collect. Ensure you 
  respect the privacy and consent of the individuals in your address book.
- **Non-Commercial:** BNPB is a personal tool. Do not sell or commercialize the 
  personal data of others stored within the app.
- **Compliance:** Follow local regulations (such as GDPR or CCPA) regarding 
  personal data management and the storage of sensitive information.

## Questions & changes
BNPB is a proprietary tool and its source code is not publicly available. 
Please report any security concerns or policy gaps through the official 
support channels.
