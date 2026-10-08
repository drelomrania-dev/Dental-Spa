# Dental Spa MVP implementation plan

## Audit snapshot

- Stack: Vite + React 19 + React Router 7, Firebase Firestore optional, localStorage fallback.
- Existing modules: dashboard, patients, patient profile, appointments, practitioners, services, payments, payment history, receivables, reports, settings.
- Existing strengths: coherent visual system, shared data context, Firebase-ready persistence, French-first UI.
- Critical gaps: no authentication or server-side authorization, permissive Firestore rules, payment records are not an immutable ledger, no booking conflict validation, no public booking, no clinical visit/treatment plan model, no price approvals, no collection sessions, and limited auditability.

## Dependency map

1. Shared data/persistence and clinic settings.
2. Appointment validation and public booking.
3. Patient clinical records and treatment plans.
4. Payment ledger, receipts, balances, and price approvals.
5. Collection sessions and scoped operational views.
6. Firebase Auth/custom claims, server-side rules/functions, and end-to-end security tests.

## Implemented in this pass

- Expanded persisted collections and seeded realistic operational data.
- Added clinic configuration defaults, booking links, staff roles, and permission metadata.
- Added backend-shaped domain helpers for appointment conflict validation, payment idempotency, balances, price approvals, and session totals.
- Added public booking route and public booking page.
- Added clinical visits, treatment plans, quotations, negotiated price requests, and collection sessions to the data model.
- Added operational documentation and a progress/test report.

## Known risks

- localStorage is suitable only for local acceptance testing; it is not a multi-user backend.
- Firebase Auth/custom claims and callable/server transaction enforcement still need deployment-specific implementation.
- Moroccan invoice/tax requirements require review with the clinic's accountant before production.

## Acceptance criteria

- A patient can submit a public booking and staff can see it internally.
- Conflicting practitioner/date/time reservations are rejected by shared domain validation.
- Payment balances derive from valid ledger entries and duplicate idempotency keys are rejected.
- Discount requests remain pending until administrator approval.
- Clinical notes are represented separately from administrative patient data.
- A collection session can be opened, reconciled, and closed.
