# Dental Spa — Clinic setup guide

## New clinic on the local stack

1. Sign in as the first administrator. The dashboard links to **Paramètres → Premiers réglages** until setup is ready.
2. Save a real clinic name, address, phone, three-letter currency and IANA timezone. These values feed the public booking identity and receipt PDF; the booking calendar uses the configured timezone for today's date.
3. Add an active practitioner in **Praticiens**, choose working days and start/end times, then add an active and booking-eligible service in **Soins & tarifs** with its price and duration.
4. Check the active chair or room in **Paramètres**, then create and publish a booking link tied to the service and resource. Open the public link and verify the identity, price and available slots before sharing it.
5. Generate each assistant or practitioner access link in **Personnel et invitations**. Send it to the intended person through an approved channel. After claim, review the member's role and active status. A practitioner claim links the Auth identity to the clinical directory.
6. Review **Rôles et permissions** and **Journal d’audit** as an administrator. Test direct route and server denials with the local SQL and authenticated browser suites.

Run the local acceptance commands in [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) before using real data. The browser demo mode is useful for previewing setup but does not verify Auth or RLS.

1. Open the production URL and sign in with the confirmed administrator account.
2. In **Paramètres**, verify clinic name, address, phone, currency `MAD` and timezone `Africa/Casablanca`.
3. Add practitioners and services with their real prices and durations.
4. Review the `consultation` public booking link before sharing it. Only active services marked as booking-eligible are shown; verify each public price, duration and description.
5. Configure Supabase Auth with a production SMTP provider and redirect URLs. Leaked-password protection is available only on Supabase Pro or above; the current Free project cannot enable it.
6. Add staff only after granular server permissions are validated for their role.
7. Run acceptance tests with non-real patient data before entering medical or financial information.
8. Configure Supabase backups, retention, monitoring and an incident/recovery owner. The current Free plan does not include scheduled project backups, so upgrade or establish an equivalent external backup procedure before real patient use.

## Production resources

- App: <https://dental-spa-taupe.vercel.app/>
- Booking: <https://dental-spa-taupe.vercel.app/book/consultation>
- Repository: <https://github.com/drelomrania-dev/Dental-Spa>

## Important limitations

- Do not treat a payment receipt as a legally validated Moroccan invoice template.
- Use the administrator-generated secure staff link for onboarding until SMTP delivery is tested; transmit it only to the intended staff member.
- Keep real clinical/financial use paused until the remaining permission and ledger acceptance tests in `MVP_TEST_REPORT.md` pass.
- The connected production project is `dental Spa OS`; its Supabase dashboard currently reports no Advisor security or performance issues, but that does not replace backups, legal review or the two-account acceptance journey.
