param([ValidateSet('start', 'stop')][string]$Mode = 'start')

$ErrorActionPreference = 'Stop'
$managerUrl = 'http://127.0.0.1:4179/'
$serverPath = Join-Path $PSScriptRoot 'repo-manager\server.mjs'
$workerPath = Join-Path $PSScriptRoot 'repo-manager\git-worker.ps1'

function Get-LocalListenerProcessId([int]$Port) {
    $pattern = "^\s*TCP\s+127\.0\.0\.1:$Port\s+0\.0\.0\.0:0\s+LISTENING\s+(\d+)\s*$"
    $entry = netstat -ano -p tcp | Select-String -Pattern $pattern | Select-Object -First 1
    if ($entry) { return [int]$entry.Matches[0].Groups[1].Value }
    return $null
}

function Stop-PortfolioService([int]$Port, [string]$ExpectedBackend) {
    $processId = Get-LocalListenerProcessId $Port
    if (-not $processId) { return $false }
    try {
        $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/version" -TimeoutSec 2
        if ($version.backend -ne $ExpectedBackend) { return $false }
        Invoke-RestMethod -Uri "http://127.0.0.1:$Port/api/shutdown" -Method Post -Headers @{ Origin = 'http://127.0.0.1:4179' } -TimeoutSec 2 | Out-Null
    } catch { return $false }

    for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
        Start-Sleep -Milliseconds 150
        if (-not (Get-LocalListenerProcessId $Port)) { return $true }
    }

    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 250
    return (-not (Get-LocalListenerProcessId $Port))
}

try {
    $nodePath = (Get-Command node.exe -ErrorAction Stop).Source
    $powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source

    if ($Mode -eq 'stop') {
        $managerStopped = Stop-PortfolioService 4179 'node-repo-icon-path-v1'
        $workerStopped = Stop-PortfolioService 4181 'powershell-project-publisher-v2'
        if ($managerStopped -or $workerStopped) {
            Write-Host 'The portfolio project manager service has stopped.' -ForegroundColor Green
        } else {
            Write-Host 'The portfolio project manager service was not running.' -ForegroundColor Yellow
        }
        exit 0
    }

    $workerProcessId = Get-LocalListenerProcessId 4181
    if ($workerProcessId) {
        try {
            $workerVersion = Invoke-RestMethod -Uri 'http://127.0.0.1:4181/api/version' -TimeoutSec 1
            if ($workerVersion.backend -ne 'powershell-project-publisher-v2') {
                Invoke-RestMethod -Uri 'http://127.0.0.1:4181/api/shutdown' -Method Post -Headers @{ Origin = 'http://127.0.0.1:4179' } -TimeoutSec 2 | Out-Null
                for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
                    Start-Sleep -Milliseconds 150
                    $workerProcessId = Get-LocalListenerProcessId 4181
                    if (-not $workerProcessId) { break }
                }
                if ($workerProcessId) {
                    Stop-Process -Id $workerProcessId -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 250
                    $workerProcessId = Get-LocalListenerProcessId 4181
                    if ($workerProcessId) { throw 'The old local Git helper did not stop. Close it, then run this launcher again.' }
                }
            }
        } catch { throw 'Port 4181 is in use by another app. Close it, then run this launcher again.' }
    }
    if (-not $workerProcessId) {
        Start-Process -FilePath $powershellPath -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$workerPath`"") -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    }
    $workerReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
        try { $worker = Invoke-RestMethod -Uri 'http://127.0.0.1:4181/api/version' -TimeoutSec 1; if ($worker.backend -eq 'powershell-project-publisher-v2') { $workerReady = $true; break } } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $workerReady) { throw 'The local Git helper did not start on port 4181.' }

    $managerProcessId = Get-LocalListenerProcessId 4179

    if ($managerProcessId) {
        try {
            $version = Invoke-RestMethod -Uri 'http://127.0.0.1:4179/api/version' -TimeoutSec 1
            if ($version.backend -ne 'node-repo-icon-path-v1') {
                Invoke-RestMethod -Uri 'http://127.0.0.1:4179/api/shutdown' -Method Post -Headers @{ Origin = 'http://127.0.0.1:4179' } -TimeoutSec 2 | Out-Null
                for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
                    Start-Sleep -Milliseconds 150
                    $managerProcessId = Get-LocalListenerProcessId 4179
                    if (-not $managerProcessId) { break }
                }
                if ($managerProcessId) {
                    Stop-Process -Id $managerProcessId -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 250
                    $managerProcessId = Get-LocalListenerProcessId 4179
                    if ($managerProcessId) { throw 'The old project manager did not stop. Close it, then run this launcher again.' }
                }
            }
        } catch { throw 'Port 4179 is in use by another app. Close it, then run this launcher again.' }
    }

    if (-not $managerProcessId) {
        Start-Process -FilePath $nodePath -ArgumentList @("`"$serverPath`"") -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    }

    $pageReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
        try {
            $page = Invoke-WebRequest -Uri $managerUrl -UseBasicParsing -TimeoutSec 1
            if ($page.Content -match 'Portfolio Project Manager') {
                $pageReady = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 300
        }
    }

    if (-not $pageReady) {
        throw 'The local project manager did not start on port 4179. Check whether another app is using that port, then try again.'
    }

    Start-Process $managerUrl
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
