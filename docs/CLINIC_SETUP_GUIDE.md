# Dental Spa — Clinic setup guide

1. Open the production URL and sign in with the confirmed administrator account.
2. In **Paramètres**, verify clinic name, address, phone, currency `MAD` and timezone `Africa/Casablanca`.
3. Add practitioners and services with their real prices and durations.
4. Review the `consultation` public booking link before sharing it.
5. Configure Supabase Auth with a production SMTP provider, redirect URLs and leaked-password protection.
6. Add staff only after granular server permissions are validated for their role.
7. Run acceptance tests with non-real patient data before entering medical or financial information.
8. Configure Supabase backups, retention, monitoring and an incident/recovery owner.

## Production resources

- App: <https://dental-spa-taupe.vercel.app/>
- Booking: <https://dental-spa-taupe.vercel.app/book/consultation>
- Repository: <https://github.com/drelomrania-dev/Dental-Spa>

## Important limitations

- Do not treat a payment receipt as a legally validated Moroccan invoice template.
- Use the administrator-generated secure staff link for onboarding until SMTP delivery is tested; transmit it only to the intended staff member.
- Keep real clinical/financial use paused until the remaining permission and ledger acceptance tests in `MVP_TEST_REPORT.md` pass.
