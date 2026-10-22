$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))

$dockerCommand = Get-Command docker.exe -ErrorAction SilentlyContinue
$dockerPath = if ($dockerCommand) { $dockerCommand.Source } else { $null }
if (-not $dockerPath) {
  $fallback = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
  if (Test-Path -LiteralPath $fallback) { $dockerPath = $fallback }
}
if (-not $dockerPath) { throw 'Docker Desktop is required to run the local SQL suites.' }

$container = (& $dockerPath ps --filter 'name=supabase_db_dentalflow-firebase' --format '{{.Names}}' | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or -not $container) { throw 'The local Supabase database container is not running.' }

$files = Get-ChildItem -LiteralPath 'supabase/tests' -Filter '*.sql' | Where-Object { $_.Name -notlike '*.template.sql' } | Sort-Object Name
foreach ($file in $files) {
  Write-Output "Running $($file.Name)"
  Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | & $dockerPath exec -i $container psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 -f -
  if ($LASTEXITCODE -ne 0) { throw "SQL acceptance failed: $($file.Name)" }
}
Write-Output "$($files.Count) local SQL acceptance suites passed."
