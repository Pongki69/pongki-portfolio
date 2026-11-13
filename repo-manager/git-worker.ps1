$ErrorActionPreference='Stop'
$hostAddress='127.0.0.1';$port=4181;$base=Split-Path -Parent $PSScriptRoot
$blockedProxy='^https?://(127\.0\.0\.1|localhost):9/?$'
foreach($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','GIT_HTTP_PROXY','GIT_HTTPS_PROXY','http_proxy','https_proxy','all_proxy','git_http_proxy','git_https_proxy')) {
    $value=[Environment]::GetEnvironmentVariable($name,'Process')
    if($value -and $value -match $blockedProxy){[Environment]::SetEnvironmentVariable($name,$null,'Process')}
}
function Send-Json($Stream,[int]$Code,$Data){$bytes=[Text.Encoding]::UTF8.GetBytes(($Data|ConvertTo-Json -Depth 10 -Compress));$reason=if($Code -eq 200){'OK'}elseif($Code -eq 403){'Forbidden'}else{'Bad Request'};$header="HTTP/1.1 $Code $reason`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`nCache-Control: no-store`r`n`r`n";$head=[Text.Encoding]::ASCII.GetBytes($header);$Stream.Write($head,0,$head.Length);$Stream.Write($bytes,0,$bytes.Length)}
function Read-Request($Stream){$memory=[IO.MemoryStream]::new();$tail=[Collections.Generic.Queue[byte]]::new();while($true){$v=$Stream.ReadByte();if($v -lt 0){break};$b=[byte]$v;$memory.WriteByte($b);$tail.Enqueue($b);if($tail.Count -gt 4){$null=$tail.Dequeue()};if($tail.Count -eq 4 -and [Text.Encoding]::ASCII.GetString($tail.ToArray()) -eq "`r`n`r`n"){break};if($memory.Length -gt 12000){throw 'Request headers are too large.'}};$lines=[Text.Encoding]::ASCII.GetString($memory.ToArray()) -split "`r`n";$first=$lines[0] -split ' ';$headers=@{};foreach($line in $lines|Select-Object -Skip 1){$i=$line.IndexOf(':');if($i -gt 0){$headers[$line.Substring(0,$i).Trim()]=$line.Substring($i+1).Trim()}};$length=0;if($headers.ContainsKey('Content-Length')){$length=[int]$headers['Content-Length']};if($length -gt 10000){throw 'Git request is too large.'};$bytes=New-Object byte[] $length;$offset=0;while($offset -lt $length){$n=$Stream.Read($bytes,$offset,$length-$offset);if($n -le 0){break};$offset+=$n};return [pscustomobject]@{Method=$first[0];Path=([uri]::new("http://${hostAddress}:${port}$($first[1])")).AbsolutePath;Headers=$headers;Body=[Text.Encoding]::UTF8.GetString($bytes,0,$offset)}}
function Invoke-AllowedGit($ArgsList) {
    $allowed = $false
    switch ([string]$ArgsList[0]) {
        'branch' { $allowed = ($ArgsList.Count -eq 2 -and $ArgsList[1] -eq '--show-current') }
        'diff' { $allowed = (($ArgsList.Count -eq 3 -and $ArgsList[1] -eq '--cached' -and $ArgsList[2] -eq '--name-only') -or ($ArgsList.Count -eq 4 -and $ArgsList[1] -eq '--name-only' -and $ArgsList[2] -eq '--' -and $ArgsList[3] -eq 'portfolio-projects.json')) }
        'fetch' { $allowed = ($ArgsList.Count -eq 3 -and $ArgsList[1] -eq 'origin' -and $ArgsList[2] -eq 'main') }
        'rev-list' { $allowed = ($ArgsList.Count -eq 3 -and $ArgsList[1] -eq '--count' -and $ArgsList[2] -in @('HEAD..origin/main','origin/main..HEAD')) }
        'add' { $allowed = ($ArgsList.Count -ge 3 -and $ArgsList[1] -eq '--' -and $ArgsList[2] -eq 'portfolio-projects.json' -and ($ArgsList.Count -eq 3 -or ($ArgsList.Count -eq 4 -and $ArgsList[3] -eq 'assets/project-icons'))) }
        'commit' { $allowed = ($ArgsList.Count -eq 2 -and $ArgsList[1] -in @('Update portfolio project details','Update portfolio project statuses')) }
        'push' { $allowed = ($ArgsList.Count -eq 3 -and $ArgsList[1] -eq 'origin' -and $ArgsList[2] -eq 'main') }
    }
    if (-not $allowed) { throw 'The Git request is not allowed.' }
    Push-Location $base
    try {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & git -c core.autocrlf=false @ArgsList 2>&1
            $exitCode = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousPreference }

        $outputText = ($output | Out-String).Trim()
        if ($exitCode -ne 0 -and $ArgsList[0] -eq 'add' -and $outputText -match 'index\.lock.*(?:File exists|already exists)') {
            $lockPath = Join-Path $base '.git\index.lock'
            $lock = Get-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue
            $activeGit = Get-Process -Name git,git-remote-https -ErrorAction SilentlyContinue
            if ($lock -and -not $activeGit -and ((Get-Date) - $lock.LastWriteTime).TotalMinutes -ge 2) {
                Remove-Item -LiteralPath $lockPath -Force
                $ErrorActionPreference = 'Continue'
                try {
                    $output = & git -c core.autocrlf=false @ArgsList 2>&1
                    $exitCode = $LASTEXITCODE
                } finally { $ErrorActionPreference = $previousPreference }
                $outputText = ($output | Out-String).Trim()
            } elseif ($lock) {
                throw 'Git has a recent index lock. Wait for any Git operation to finish, then retry the save.'
            }
        }
        if ($exitCode -ne 0) { throw $outputText }
        return (($output | Out-String).Trim())
    } finally { Pop-Location }
}
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($hostAddress),$port);$listener.Start();Write-Output "Portfolio Git worker listening on http://${hostAddress}:${port}"
while($true){$client=$null;try{$client=$listener.AcceptTcpClient();$stream=$client.GetStream();$stream.ReadTimeout=120000;$request=Read-Request $stream;$responseCode=200;$body=@{backend='powershell-native-manager-retry3'};if($request.Headers['Host'] -ne "${hostAddress}:${port}"){$responseCode=403;$body=@{error='Use the local Git worker address.'}}elseif($request.Method -eq 'GET' -and $request.Path -eq '/api/version'){$body=@{backend='powershell-native-manager-retry3'}}elseif($request.Method -eq 'POST' -and $request.Path -in @('/api/git','/api/shutdown') -and $request.Headers['Origin'] -ne 'http://127.0.0.1:4179'){$responseCode=403;$body=@{error='The Git worker only accepts requests from the local project manager.'}}elseif($request.Method -eq 'POST' -and $request.Path -eq '/api/git'){try{$payload=$request.Body|ConvertFrom-Json;$body=@{stdout=(Invoke-AllowedGit @($payload.args))}}catch{$responseCode=400;$body=@{error=$_.Exception.Message}}}elseif($request.Method -eq 'POST' -and $request.Path -eq '/api/shutdown'){Send-Json $stream 200 @{message='Git worker closing.'};$listener.Stop();break}else{$responseCode=404;$body=@{error='Git worker route not found.'}};Send-Json $stream $responseCode $body}catch{if($client -and $client.Connected){try{Send-Json $client.GetStream() 400 @{error=$_.Exception.Message}}catch{}}}finally{if($client){$client.Close()}}};$listener.Stop()
