# Notification permission sanity check

## Scenario
Confirm that accepting the standard notification prompt no longer triggers an
automatic redirect to Android's system settings. The extra navigation should
only occur when the user explicitly opts into the exact-alarm permission from
the settings screen.

## Preconditions
- Fresh install or clear app data so the notification and exact-alarm
  permissions are unset.
- Device running Android 12 or newer.

## Steps
1. Launch the app and proceed past onboarding until the notification settings
   tab is available.
2. Accept the standard notification permission prompt when it appears.
3. Verify that the app stays in the foreground; Android should not open the
   system settings screen automatically.
4. Navigate to **Settings → Precise scheduling** and toggle **Allow exact alarm
   scheduling** on.
5. Observe the explanatory dialog and choose **Continue**.
6. Confirm that Android now opens the system dialog or settings screen to grant
   the exact-alarm permission.

## Expected results
- Accepting the notification permission alone keeps the user inside the app.
- The explanatory dialog appears before the exact-alarm request is fired.
- Android only leaves the app after the user confirms the opt-in.
