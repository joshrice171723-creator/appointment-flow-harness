$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$buildTime = [Diagnostics.Stopwatch]::StartNew()
docker compose build
if ($LASTEXITCODE) { throw 'Appointment Flow image build failed. Check Docker Desktop and the build output.' }
Write-Host ('Images ready in {0:n1}s.' -f $buildTime.Elapsed.TotalSeconds)

$startupTime = [Diagnostics.Stopwatch]::StartNew()
docker compose up --no-build -d --wait --wait-timeout 900
if ($LASTEXITCODE) { throw 'Appointment Flow did not become ready. Check docker compose logs setup app worker.' }
docker compose ps -a
$address = docker compose port app 8174
if ($LASTEXITCODE) { throw 'Appointment Flow started, but its host port could not be read.' }
Write-Host ('Appointment Flow is ready at http://{0}/ after {1:n1}s of startup.' -f $address, $startupTime.Elapsed.TotalSeconds)
