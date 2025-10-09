# Manual QA: Legacy JSON import/export regression

## Goal
Ensure exporting a contact to JSON and importing it multiple times keeps a single record per contact by leveraging stable IDs and `ConflictAlgorithm.replace`.

## Preconditions
- A debug or profile build of the app installed on a device or emulator.
- At least one contact exists (or create one during the steps below).
- Access to the device file system or desktop to store exported files.

## Steps
1. Launch the app and create a contact named "Test Legacy" if one does not already exist.
2. Open the overflow menu on the home screen and choose **Export**.
3. Select **JSON** export with any combination of fields (ID is always included automatically) and save the generated file to local storage.
4. Return to the app and open the overflow menu again, then choose **Restore** → **Legacy JSON import**.
5. Pick the JSON file created in step 3. Confirm the success snackbar appears.
6. Repeat step 4 and step 5 using the same JSON file to perform a second import.
7. Navigate back to the home screen and ensure only a single "Test Legacy" contact is listed (no duplicates).
8. Optionally, inspect the database with the existing developer tooling to confirm only one row exists for the contact ID recorded in the JSON export.

## Expected Results
- The exported JSON contains an `id` property for each contact regardless of the selected fields.
- After importing the same JSON file twice, only one "Test Legacy" contact exists in the contact list.
- No error snackbars appear during the import operations.
