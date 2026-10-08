# MVP progress

**Module:** Foundation
**Implemented:** Expanded domain collections, clinic configuration defaults, roles/permissions metadata, and shared domain validation.
**Verified:** Production build passes after implementation.
**Remaining:** Firebase Authentication, custom claims, server-enforced authorization.
**Risks / blockers:** localStorage fallback is single-browser only.

**Module:** Booking
**Implemented:** Internal appointment conflict checks and public `/book/:slug` flow.
**Verified:** Local data persistence and duplicate-slot validation in the shared context.
**Remaining:** Atomic Firestore transaction/cloud function and abuse rate limiting.
**Risks / blockers:** Public deployment needs Firebase App Check or an equivalent edge rate limiter.

**Module:** Clinical and finance
**Implemented:** Visits, treatment plans, quotations, price approval requests, ledger-aware payments, and collection sessions in the application model.
**Verified:** Build and local persistence checks.
**Remaining:** Full UI workflows and server-side transaction tests.
**Risks / blockers:** Fiscal invoice requirements must be configured and reviewed for Morocco.

**Verification:** Final JSX/CSS bundle check passed on 8 October 2026. Full Vite build is blocked by the OneDrive realpath restriction in this desktop environment.

**Module:** Staff operations
**Implemented:** Clinical consultation screen, negotiated-price request/approval screen, and daily collection session open/submit screen. Added navigation and payment collector/session metadata.
**Verified:** Final JSX/CSS bundle check passed after these screens were added.
**Remaining:** Role-aware route guards, administrator validation/reopen workflow, and server-side enforcement.
**Risks / blockers:** The current local fallback intentionally has no multi-user identity boundary.

**Module:** Permissions and public availability
**Implemented:** Local role switcher for administrator, assistant, and practitioner profiles; navigation filtering; public slots now disable occupied practitioner times.
**Verified:** Final JSX/CSS bundle check passed after the permission and availability changes.
**Remaining:** Replace local role simulation with Firebase Auth/custom claims and atomic server-side availability checks.
**Risks / blockers:** Client-side filtering is not a security boundary and must not be used alone for production patient data.

**Module:** Local-first persistence
**Implemented:** LocalStorage is now the explicit default; Firebase requires `VITE_USE_FIREBASE=true` plus valid credentials. Settings clearly shows the active storage mode.
**Verified:** Local-storage build check passed.
**Remaining:** Add an explicit export/import backup flow before using local mode with important clinic data.
**Risks / blockers:** LocalStorage is browser-specific and can be lost when browser data is cleared.

**Module:** Supabase preparation
**Implemented:** Versioned Postgres schema with clinic scoping, monetary precision, idempotency keys, audit events, indexes, and RLS enabled fail-closed. Added migration and rollout guidance.
**Verified:** Application bundle still passes after schema/documentation changes.
**Remaining:** Apply and review the schema in a non-production Supabase branch; implement the adapter and clinic-scoped RLS policies.
**Risks / blockers:** Direct Supabase SQL execution is not exposed as a callable tool in this session, so no remote database changes were made.

**Module:** Local backup and recovery
**Implemented:** JSON export and validated restore of localStorage collections and clinic settings from the Settings screen.
**Verified:** Local backup build check passed.
**Remaining:** Test restore with a full acceptance dataset and document an off-device backup cadence.
**Risks / blockers:** The user must store exported backup files securely because they may contain patient information.
