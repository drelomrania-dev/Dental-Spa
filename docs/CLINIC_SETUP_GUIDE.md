# Clinic setup guide

1. Configure Firebase Authentication and create individual staff accounts.
2. Replace the starter Firestore rules with role- and clinic-scoped rules.
3. Configure the clinic name, address, hours, timezone (`Africa/Casablanca`) and currency (`MAD`) in Settings.
4. Add practitioners and services with real durations and prices.
5. Review payment methods, receipt numbering, and invoice requirements with the clinic accountant.
6. Publish only the booking links intended for patients.
7. Test booking, clinical visit, price approval, payment, receipt, and cash closing with non-production data.
8. Configure backups, retention, incident response, and access review before importing real patient records.

## LocalStorage mode

While Firebase is not active, use Settings → Exporter une sauvegarde after meaningful testing sessions. Store the JSON file in a protected location. Restore only a Dental Spa backup created by this application and verify the data after reload.
