# Optional Facial Recognition Pipeline Research

This document outlines a **non-default** facial-recognition extension that could
augment the visual recognition cues in the contacts app. The pipeline is
strictly opt-in and must ship behind a dedicated consent gate before any
implementation work proceeds.

## Target Outcomes

* Offer a fast way to attach and search recognition photos for contacts.
* Run entirely on-device so that biometric data never leaves the user’s
  hardware unless they explicitly export it.
* Remain replaceable – if regulations or user feedback change, the feature can
  be removed without corrupting existing contact data (photo cues continue to
  work as plain images).

## Reference Architecture

1. **Enrollment (per contact)**
   * Capture multiple face images (or reuse the existing photo cues) with
     explicit consent.
   * Use a lightweight detector such as
     [`google_mlkit_face_detection`](https://pub.dev/packages/google_mlkit_face_detection)
     or `mediapipe` to crop faces. Keep the raw image only locally.
   * Generate embeddings with an on-device model. Options include:
     * [`tflite_flutter`](https://pub.dev/packages/tflite_flutter) running a
       MobileFaceNet or FaceNet variant.
     * [`google_mlkit_face_recognition`](https://developers.google.com/ml-kit/vision/face-recognition)
       once it exits beta (currently region-limited).
   * Store the resulting 128–256 dimensional vector encrypted in the app’s
     database alongside metadata linking it to the contact.

2. **Matching/Search**
   * When the user adds a new recognition photo or takes a quick snapshot,
     repeat the embedding step and compare against stored vectors using cosine
     similarity or Euclidean distance.
   * Set a configurable decision threshold (e.g., cosine similarity ≥ 0.6) to
     account for lighting/pose differences.
   * Surface the suggested contact match to the user for manual confirmation;
     never auto-attach without approval.

3. **Model Management**
   * Bundle a default quantized model with the app. Keep the download size in
     check by pruning channels and using 8-bit quantization (~2–4 MB).
   * Offer a background job that refreshes the model when an updated version is
     published, using HTTPS and verifying SHA-256 hashes before install.

## Privacy & Compliance Checklist

* **Informed consent:** Require an explicit opt-in per contact (and global
  setting) describing what biometric templates are stored and how they are used.
* **Data minimization:** Retain only embeddings + small thumbnails. Source
  images should be user-managed photo cues that can be deleted at any time.
* **Local storage & encryption:** Store embeddings in an encrypted table (e.g.,
  `sqflite_sqlcipher` on mobile). Do not sync via cloud backups without an
  additional encrypted export format.
* **Right to be forgotten:** Provide a one-tap way to purge embeddings for a
  single contact or the entire vault.
* **Regulatory review:** Verify applicability of GDPR, CCPA, BIPA, and other
  biometric laws in target regions. Many jurisdictions require a public policy
  describing retention and destruction timelines.
* **Security hardening:**
  * Protect the embedding model and stored vectors with device authentication
    (biometrics/PIN) before allowing access.
  * Obfuscate the inference layer to discourage model extraction.

## Implementation Status

*No code has been added.* This document captures the recommended research path
so the team can evaluate feasibility, legal requirements, and UX trade-offs
before committing to a build.
