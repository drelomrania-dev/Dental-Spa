param([switch]$Reset)

$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))

$dockerCommand = Get-Command docker.exe -ErrorAction SilentlyContinue
$dockerPath = if ($dockerCommand) { $dockerCommand.Source } else { $null }
if (-not $dockerPath) {
  $fallback = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
  if (Test-Path -LiteralPath $fallback) { $dockerPath = $fallback }
}
if (-not $dockerPath) { throw 'Docker Desktop is required for the local Supabase stack.' }
& $dockerPath info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop and complete its setup before running this script.' }

& pnpm dlx supabase start | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Local Supabase failed to start.' }
if ($Reset) {
  & pnpm dlx supabase db reset --local --no-seed | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Local database reset failed.' }
}

$statusLines = & pnpm dlx supabase status -o env
if ($LASTEXITCODE -ne 0) { throw 'Cannot read local Supabase status.' }
$status = @{}
foreach ($line in $statusLines) {
  if ($line -match '^([A-Z_]+)=(.*)$') { $status[$matches[1]] = $matches[2].Trim('"') }
}
if ($status.API_URL -ne 'http://127.0.0.1:54321' -and $status.API_URL -ne 'http://localhost:54321') {
  throw 'Local API URL is unexpected; fixture setup was refused.'
}
if (-not $status.ANON_KEY -or -not $status.SERVICE_ROLE_KEY) { throw 'Local Supabase keys are unavailable.' }

try {
  $env:LOCAL_SUPABASE_URL = $status.API_URL
  $env:LOCAL_SUPABASE_ANON_KEY = $status.ANON_KEY
  $env:LOCAL_SUPABASE_SERVICE_ROLE_KEY = $status.SERVICE_ROLE_KEY
  & node scripts/seed-local.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Local fixture setup failed.' }
  & node scripts/verify-local.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Local service acceptance failed after fixture setup.' }
} finally {
  Remove-Item Env:LOCAL_SUPABASE_URL, Env:LOCAL_SUPABASE_ANON_KEY, Env:LOCAL_SUPABASE_SERVICE_ROLE_KEY -ErrorAction SilentlyContinue
}

Write-Output 'Run scripts/local-dev.ps1 for the app, then scripts/local-e2e.ps1 for browser checks.'
