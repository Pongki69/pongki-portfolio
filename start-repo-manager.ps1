$ErrorActionPreference = 'Stop'
$managerUrl = 'http://127.0.0.1:4179/'
$serverPath = Join-Path $PSScriptRoot 'repo-manager\server.mjs'

try {
    $nodePath = (Get-Command node.exe -ErrorAction Stop).Source
    $existingListener = Get-NetTCPConnection -LocalPort 4179 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1

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
