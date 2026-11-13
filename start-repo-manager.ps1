$ErrorActionPreference = 'Stop'
$managerUrl = 'http://127.0.0.1:4179/'
$serverPath = Join-Path $PSScriptRoot 'repo-manager\server.mjs'
$workerPath = Join-Path $PSScriptRoot 'repo-manager\git-worker.ps1'

try {
    $nodePath = (Get-Command node.exe -ErrorAction Stop).Source
    $powershellPath = (Get-Command powershell.exe -ErrorAction Stop).Source

    $workerListener = Get-NetTCPConnection -LocalPort 4181 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($workerListener) {
        try {
            $workerVersion = Invoke-RestMethod -Uri 'http://127.0.0.1:4181/api/version' -TimeoutSec 1
            if ($workerVersion.backend -ne 'powershell-native') {
                Invoke-RestMethod -Uri 'http://127.0.0.1:4181/api/shutdown' -Method Post -Headers @{ Origin = 'http://127.0.0.1:4179' } -TimeoutSec 2 | Out-Null
                Start-Sleep -Milliseconds 300
                $workerListener = Get-NetTCPConnection -LocalPort 4181 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        } catch { throw 'Port 4181 is in use by another app. Close it, then run this launcher again.' }
    }
    if (-not $workerListener) {
        Start-Process -FilePath $powershellPath -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$workerPath`"") -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
    }
    $workerReady = $false
    for ($attempt = 0; $attempt -lt 20; $attempt += 1) {
        try { $worker = Invoke-RestMethod -Uri 'http://127.0.0.1:4181/api/version' -TimeoutSec 1; if ($worker.backend -eq 'powershell-native') { $workerReady = $true; break } } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $workerReady) { throw 'The local Git helper did not start on port 4181.' }

    $existingListener = Get-NetTCPConnection -LocalPort 4179 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($existingListener) {
        try {
            $version = Invoke-RestMethod -Uri 'http://127.0.0.1:4179/api/version' -TimeoutSec 1
            if ($version.backend -ne 'node-git-worker') {
                Invoke-RestMethod -Uri 'http://127.0.0.1:4179/api/shutdown' -Method Post -Headers @{ Origin = 'http://127.0.0.1:4179' } -TimeoutSec 2 | Out-Null
                Start-Sleep -Milliseconds 400
                $existingListener = Get-NetTCPConnection -LocalPort 4179 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        } catch { throw 'Port 4179 is in use by another app. Close it, then run this launcher again.' }
    }

    if (-not $existingListener) {
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
