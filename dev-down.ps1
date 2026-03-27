[CmdletBinding()]
param(
  [switch]$ForcePorts,
  [int]$RedisPort = 6379,
  [int]$BackendPort = 8080,
  [int]$FrontendPort = 3000
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[dev-down] $Message"
}

function Get-ListeningPids {
  param([int]$Port)
  $lines = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
  if (-not $lines) { return @() }
  $procIds = @()
  foreach ($line in $lines) {
    $parts = ($line -split "\s+") | Where-Object { $_ -ne "" }
    if ($parts.Count -lt 5) { continue }
    $pidText = $parts[-1]
    $procId = 0
    if ([int]::TryParse($pidText, [ref]$procId) -and $procId -gt 0) { $procIds += $procId }
  }
  return $procIds | Sort-Object -Unique
}

function Stop-ByPid {
  param(
    [int]$ProcessId,
    [string]$Name
  )
  try {
    $proc = Get-Process -Id $ProcessId -ErrorAction Stop
    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
    Write-Step "Stopped $Name PID $ProcessId"
    return $true
  } catch {
    Write-Step "$Name PID $ProcessId not running"
    return $false
  }
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateFile = Join-Path $root ".tmp\dev\pids.json"

$state = $null
if (Test-Path $stateFile) {
  try {
    $state = Get-Content -Raw -Path $stateFile | ConvertFrom-Json
    Write-Step "Loaded state from $stateFile"
  } catch {
    Write-Step "State file exists but failed to parse, fallback by ports."
  }
} else {
  Write-Step "State file not found, fallback by ports."
}

$managedPorts = @{}
$redisManagedByDevUp = $false

if ($state -and $state.services) {
  foreach ($svcName in @("frontend", "backend", "redis")) {
    $svc = $state.services.$svcName
    if (-not $svc) { continue }
    $managed = [bool]$svc.managed
    $procId = [int]$svc.pid
    $port = [int]$svc.port
    $managedPorts[$port] = $managed

    if ($svcName -eq "redis") {
      $redisManagedByDevUp = $managed
      if ($managed -and $procId -gt 0) {
        [void](Stop-ByPid -ProcessId $procId -Name $svcName)
      } elseif ($managed) {
        Write-Step "$svcName marked managed but PID missing, will use port fallback."
      } else {
        Write-Step "redis was not started by dev-up, keep running."
      }
    } else {
      if ($procId -gt 0) {
        [void](Stop-ByPid -ProcessId $procId -Name $svcName)
      } else {
        Write-Step "$svcName PID missing, will use port fallback."
      }
    }
  }

  foreach ($port in @($FrontendPort, $BackendPort)) {
    $procIds = Get-ListeningPids -Port $port
    foreach ($procId in $procIds) {
      [void](Stop-ByPid -ProcessId $procId -Name "port-$port")
    }
  }

  if ($redisManagedByDevUp) {
    $procIds = Get-ListeningPids -Port $RedisPort
    foreach ($procId in $procIds) {
      [void](Stop-ByPid -ProcessId $procId -Name "port-$RedisPort")
    }
  }
}

if ($ForcePorts -or -not $state) {
  Write-Step "Force/fallback stop by ports: $FrontendPort, $BackendPort"
  foreach ($port in @($FrontendPort, $BackendPort)) {
    $procIds = Get-ListeningPids -Port $port
    foreach ($procId in $procIds) {
      [void](Stop-ByPid -ProcessId $procId -Name "port-$port")
    }
  }
  if ($state -and $redisManagedByDevUp) {
    $procIds = Get-ListeningPids -Port $RedisPort
    foreach ($procId in $procIds) {
      [void](Stop-ByPid -ProcessId $procId -Name "port-$RedisPort")
    }
  }
}

if (Test-Path $stateFile) {
  Remove-Item -Path $stateFile -Force -ErrorAction SilentlyContinue
  Write-Step "Removed state file."
}

$remainingFrontendBackend = @()
foreach ($port in @($FrontendPort, $BackendPort)) {
  $p = Get-ListeningPids -Port $port
  if ($p.Count -gt 0) {
    $remainingFrontendBackend += "port $port => $($p -join ',')"
  }
}

$remainingRedis = Get-ListeningPids -Port $RedisPort

if ($remainingFrontendBackend.Count -gt 0) {
  Write-Step "Some frontend/backend listeners remain:"
  $remainingFrontendBackend | ForEach-Object { Write-Host "  $_" }
} else {
  Write-Step "Done. Frontend/backend are stopped."
}

if ($remainingRedis.Count -gt 0) {
  if ($state -and -not $redisManagedByDevUp) {
    Write-Step "Redis listener remains (expected, not started by dev-up): port $RedisPort => $($remainingRedis -join ',')"
  } elseif ($state -and $redisManagedByDevUp) {
    Write-Step "Redis listener still remains (unexpected): port $RedisPort => $($remainingRedis -join ',')"
  } else {
    Write-Step "Redis listener remains (no state file, preserved): port $RedisPort => $($remainingRedis -join ',')"
  }
} else {
  if ($state -and $redisManagedByDevUp) {
    Write-Step "Redis stopped (started by dev-up)."
  } else {
    Write-Step "Redis not running."
  }
}
