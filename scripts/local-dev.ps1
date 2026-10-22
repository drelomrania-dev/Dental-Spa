$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$fixture = Get-Content -LiteralPath '.local-fixtures.json' -Raw | ConvertFrom-Json
if ($fixture.supabaseUrl -ne 'http://127.0.0.1:54321' -and $fixture.supabaseUrl -ne 'http://localhost:54321') {
  throw 'Refusing a nonlocal Supabase target.'
}
$env:VITE_DATA_BACKEND = 'supabase'
$env:VITE_SUPABASE_URL = $fixture.supabaseUrl
$env:VITE_SUPABASE_ANON_KEY = $fixture.anonKey
$env:VITE_PUBLIC_APP_URL = 'http://127.0.0.1:4173'
$env:VITE_ENABLE_DEMO_SEED = 'false'
$env:VITE_USE_FIREBASE = 'false'
& pnpm dev --host 127.0.0.1 --port 4173
