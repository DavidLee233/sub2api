[CmdletBinding()]
param(
  [string]$RedisExe = "D:\Redis\redis-server.exe",
  [int]$RedisPort = 6379,
  [int]$BackendPort = 8080,
  [int]$FrontendPort = 3000
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[dev-up] $Message"
}

function Get-ListeningPid {
  param([int]$Port)
  $line = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING" | Select-Object -First 1
  if (-not $line) { return $null }
  $parts = ($line -split "\s+") | Where-Object { $_ -ne "" }
  if ($parts.Count -lt 5) { return $null }
  $pidText = $parts[-1]
  $procId = 0
  if ([int]::TryParse($pidText, [ref]$procId) -and $procId -gt 0) { return $procId }
  return $null
}

function Wait-Port {
  param(
    [int]$Port,
    [int]$TimeoutSec = 30
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $procId = Get-ListeningPid -Port $Port
    if ($procId) { return $procId }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Wait-Http {
  param(
    [string]$Url,
    [int]$TimeoutSec = 30
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
      if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) { return $true }
    } catch {
      # keep waiting
    }
    Start-Sleep -Milliseconds 800
  }
  return $false
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $root "backend"
$frontendDir = Join-Path $root "frontend"
$stateDir = Join-Path $root ".tmp\dev"
$logDir = Join-Path $stateDir "logs"
$stateFile = Join-Path $stateDir "pids.json"
$backendDataDir = $backendDir
$frontendHome = Join-Path $stateDir "home"
$frontendTmp = Join-Path $stateDir "tmp"
$backendLog = Join-Path $logDir "backend.log"
$frontendLog = Join-Path $logDir "frontend.log"

New-Item -ItemType Directory -Force -Path $stateDir, $logDir, $frontendHome, $frontendTmp | Out-Null

if (-not (Test-Path $RedisExe)) {
  throw "Redis executable not found: $RedisExe"
}
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
  throw "go command not found in PATH"
}
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  throw "pnpm command not found in PATH"
}

$services = [ordered]@{}

# Redis
$redisPid = Get-ListeningPid -Port $RedisPort
$redisManaged = $false
if ($redisPid) {
  Write-Step "Redis already listening on :$RedisPort (PID $redisPid), skip start."
} else {
  Write-Step "Starting Redis..."
  $redisArgs = @(
    "--port", "$RedisPort",
    "--bind", "127.0.0.1",
    "--dir", (Join-Path $backendDir "data"),
    "--save", "900", "1",
    "--save", "300", "10",
    "--save", "60", "10000",
    "--syslog-enabled", "no"
  )
  Start-Process -FilePath $RedisExe -ArgumentList $redisArgs -WindowStyle Hidden | Out-Null
  $redisPid = Wait-Port -Port $RedisPort -TimeoutSec 20
  if (-not $redisPid) {
    throw "Redis did not start on port $RedisPort"
  }
  $redisManaged = $true
  Write-Step "Redis started (PID $redisPid)."
}
$services.redis = @{
  managed = $redisManaged
  pid = $redisPid
  port = $RedisPort
}

# Backend
$backendPid = Get-ListeningPid -Port $BackendPort
$backendManaged = $false
if ($backendPid) {
  Write-Step "Backend already listening on :$BackendPort (PID $backendPid), skip start."
} else {
  Write-Step "Starting backend..."
  "[$(Get-Date -Format s)] starting backend" | Add-Content -Path $backendLog
  $backendCmd = "& { `$env:DATA_DIR='$backendDataDir'; Set-Location '$backendDir'; go run ./cmd/server/ } *>> '$backendLog'"
  Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @("-NoProfile", "-Command", $backendCmd) -WindowStyle Hidden | Out-Null
  $ready = Wait-Http -Url "http://127.0.0.1:$BackendPort/health" -TimeoutSec 45
  if (-not $ready) {
    throw "Backend did not become healthy on http://127.0.0.1:$BackendPort/health. Check $backendLog"
  }
  $backendPid = Get-ListeningPid -Port $BackendPort
  if (-not $backendPid) {
    throw "Backend health endpoint responded but no listening PID found on port $BackendPort"
  }
  $backendManaged = $true
  Write-Step "Backend started (PID $backendPid)."
}
$services.backend = @{
  managed = $backendManaged
  pid = $backendPid
  port = $BackendPort
  health = "http://127.0.0.1:$BackendPort/health"
}

# Frontend
$frontendPid = Get-ListeningPid -Port $FrontendPort
$frontendManaged = $false
if ($frontendPid) {
  Write-Step "Frontend already listening on :$FrontendPort (PID $frontendPid), skip start."
} else {
  Write-Step "Starting frontend..."
  "[$(Get-Date -Format s)] starting frontend" | Add-Content -Path $frontendLog
  $frontendCmd = "& { `$env:HOME='$frontendHome'; `$env:USERPROFILE='$frontendHome'; `$env:TEMP='$frontendTmp'; `$env:TMP='$frontendTmp'; Set-Location '$frontendDir'; pnpm dev } *>> '$frontendLog'"
  Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @("-NoProfile", "-Command", $frontendCmd) -WindowStyle Hidden | Out-Null
  $frontendPid = Wait-Port -Port $FrontendPort -TimeoutSec 60
  if (-not $frontendPid) {
    throw "Frontend did not start on port $FrontendPort. Check $frontendLog"
  }
  $frontendReady = Wait-Http -Url "http://127.0.0.1:$FrontendPort" -TimeoutSec 20
  if (-not $frontendReady) {
    throw "Frontend port opened but HTTP not ready on http://127.0.0.1:$FrontendPort. Check $frontendLog"
  }
  $frontendManaged = $true
  Write-Step "Frontend started (PID $frontendPid)."
}
$services.frontend = @{
  managed = $frontendManaged
  pid = $frontendPid
  port = $FrontendPort
  url = "http://127.0.0.1:$FrontendPort"
}

$state = [ordered]@{
  updated_at = (Get-Date).ToString("s")
  root = $root
  services = $services
  logs = @{
    backend = $backendLog
    frontend = $frontendLog
  }
}
$state | ConvertTo-Json -Depth 6 | Set-Content -Path $stateFile -Encoding UTF8

Write-Step "All services are ready."
Write-Host "Frontend: http://127.0.0.1:$FrontendPort"
Write-Host "Backend:  http://127.0.0.1:$BackendPort/health"
Write-Host "Redis:    127.0.0.1:$RedisPort"
Write-Host "State:    $stateFile"
Write-Host "Logs:     $logDir"
