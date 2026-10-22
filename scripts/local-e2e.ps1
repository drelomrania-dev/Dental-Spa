$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$fixture = Get-Content -LiteralPath '.local-fixtures.json' -Raw | ConvertFrom-Json
if ($fixture.supabaseUrl -ne 'http://127.0.0.1:54321' -and $fixture.supabaseUrl -ne 'http://localhost:54321') {
  throw 'Refusing a nonlocal Supabase target.'
}
if ($env:E2E_BASE_URL) { throw 'Unset E2E_BASE_URL before local acceptance; an external browser target is not allowed here.' }
if ($fixture.baseUrl -ne 'http://127.0.0.1:4173') { throw 'Unexpected local app URL in fixture.' }
$statusLines = & pnpm dlx supabase status -o env
if ($LASTEXITCODE -ne 0) { throw 'Local Supabase is not running.' }
$status = @{}
foreach ($line in $statusLines) {
  if ($line -match '^([A-Z_]+)=(.*)$') { $status[$matches[1]] = $matches[2].Trim('"') }
}
if ($status.API_URL -ne $fixture.supabaseUrl -or -not $status.SERVICE_ROLE_KEY) {
  throw 'Fixture target does not match the running local Supabase stack.'
}

try {
  $env:LOCAL_SUPABASE_SERVICE_ROLE_KEY = $status.SERVICE_ROLE_KEY
  $env:E2E_SUPABASE_URL = $fixture.supabaseUrl
  $env:E2E_SUPABASE_ANON_KEY = $fixture.anonKey
  $env:E2E_ADMIN_EMAIL = $fixture.accounts.admin.email
  $env:E2E_ADMIN_PASSWORD = $fixture.accounts.admin.password
  $env:E2E_ASSISTANT_EMAIL = $fixture.accounts.assistant.email
  $env:E2E_ASSISTANT_PASSWORD = $fixture.accounts.assistant.password
  $env:E2E_OTHER_ADMIN_EMAIL = $fixture.accounts.otherAdmin.email
  $env:E2E_OTHER_ADMIN_PASSWORD = $fixture.accounts.otherAdmin.password
  $env:E2E_REQUIRE_FRESH_SERVER = '1'
  & node scripts/verify-local.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Local Auth, tenant, Storage, or Edge Function acceptance failed.' }
  & pnpm e2e
  if ($LASTEXITCODE -ne 0) { throw 'Local browser acceptance failed.' }
} finally {
  Remove-Item Env:LOCAL_SUPABASE_SERVICE_ROLE_KEY, Env:E2E_SUPABASE_URL, Env:E2E_SUPABASE_ANON_KEY, Env:E2E_ADMIN_EMAIL, Env:E2E_ADMIN_PASSWORD, Env:E2E_ASSISTANT_EMAIL, Env:E2E_ASSISTANT_PASSWORD, Env:E2E_OTHER_ADMIN_EMAIL, Env:E2E_OTHER_ADMIN_PASSWORD, Env:E2E_REQUIRE_FRESH_SERVER -ErrorAction SilentlyContinue
}
