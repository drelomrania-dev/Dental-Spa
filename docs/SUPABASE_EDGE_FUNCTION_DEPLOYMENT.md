# Supabase Edge Function deployment

This runbook deploys `staff-invite-link` without putting project identifiers or
secret values in the repository. Run it from the repository root, and use a
staging project first.

## Prerequisites

- Supabase CLI installed and authenticated with an account allowed to deploy
  Edge Functions.
- A project ref selected by the operator. Do not copy a ref from another
  environment.
- The four server-side values available through the approved secret manager:
  `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `PUBLIC_APP_URL`, and
  `ALLOWED_ORIGINS`.
- The production or staging origin is included in `PUBLIC_APP_URL` or
  `ALLOWED_ORIGINS`. `ALLOWED_ORIGINS` is a comma-separated list of exact
  origins, without paths or credentials.

## Deploy

Set these values in the shell or CI secret store. The placeholders below are
names, not values; never commit a populated version of this block.

```bash
export SUPABASE_PROJECT_REF='<PROJECT_REF_FROM_OPERATOR>'
export SUPABASE_URL='<SUPABASE_URL_FROM_SECRET_MANAGER>'
export SUPABASE_SERVICE_ROLE_KEY='<SERVICE_ROLE_KEY_FROM_SECRET_MANAGER>'
export PUBLIC_APP_URL='<CANONICAL_APP_ORIGIN>'
export ALLOWED_ORIGINS='<OPTIONAL_COMMA_SEPARATED_EXACT_ORIGINS>'
```

Verify the target before deployment, then set the function secrets and deploy:

```bash
supabase projects list
supabase secrets set \
  --project-ref "$SUPABASE_PROJECT_REF" \
  SUPABASE_URL="$SUPABASE_URL" \
  SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
  PUBLIC_APP_URL="$PUBLIC_APP_URL" \
  ALLOWED_ORIGINS="$ALLOWED_ORIGINS"
supabase functions deploy staff-invite-link --project-ref "$SUPABASE_PROJECT_REF"
```

If the secrets already exist, re-run the `secrets set` command only when a
value changed. Never echo the values, place them in a command committed to
source control, or expose `SUPABASE_SERVICE_ROLE_KEY` to the browser.

The deployment command is intentionally explicit about the function name and
project ref. No project ref is stored in this repository.

## Post-deploy smoke checks

Set the function URL from the same operator-selected project ref; do not
invent or copy a ref from another environment.

```bash
export FUNCTION_URL="https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/staff-invite-link"
```

The following checks must be performed without printing response bodies that
could contain access links:

1. Anonymous request: `POST` with no `Authorization` header returns `401`.
2. Non-administrator bearer token returns `403`.
3. A request from an unapproved `Origin` does not receive an
   `Access-Control-Allow-Origin` header.
4. An administrator using a real pending invitation token and an approved
   `/join/<token>` redirect receives `200` and an action link.
5. An administrator using a redirect outside an approved origin or outside
   `/join/` receives `400`.
6. Repeat checks from every approved production or staging origin.

Example safe status-only checks:

```bash
test "$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$FUNCTION_URL")" = 401
test "$(curl -sS -o /dev/null -w '%{http_code}' -X OPTIONS \
  -H 'Origin: https://unapproved.invalid' "$FUNCTION_URL")" = 200
```

The second check must also be inspected to confirm that the response has no
`Access-Control-Allow-Origin` header. Authenticated checks require staging
accounts and a disposable invitation; do not use real patient data for this
smoke test.

## Rollback and evidence

Record the deployment timestamp, operator, target environment, function
version/commit, and smoke-check results. If the function is unhealthy, redeploy
the last known-good commit using the same explicit project ref and restore the
previous secret values from the approved secret manager. Do not paste secret
values into the release record.
