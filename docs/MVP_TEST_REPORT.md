# MVP test report

## Executed

- JSX/CSS production bundle check with the bundled esbuild runtime — **PASS**.
- `npm run build` — blocked in the OneDrive checkout because Vite cannot `realpath` the synced workspace path; this is an environment limitation, not a transform failure.
- Local persistence smoke test — dataStore preserves records between reloads.
- Domain validation review — appointment overlaps, duplicate payment idempotency keys, and balance derivation are centralized.
- Browser smoke test against the running local app — dashboard, appointments, payments, clinical, approvals, collection sessions, settings, and public booking routes loaded successfully.
- Public booking availability check — the occupied `10:30` slot was visibly disabled on the public consultation page.

## Not yet production-verified

- Two-client Firestore booking race.
- Firebase Auth role claims and Firestore rules.
- Browser end-to-end tests.
- Moroccan legal invoice review.

## Result

The current repository remains a local/Firebase-ready MVP and is not yet safe for real patient data until authentication, restrictive Firestore rules, backups, and deployment-specific security review are completed.
