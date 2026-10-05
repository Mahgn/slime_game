@echo off
setlocal
set "HERO_JOURNEY_ROOT=%~dp0"
set "HERO_JOURNEY_PORT=%~1"
if not defined HERO_JOURNEY_PORT set "HERO_JOURNEY_PORT=8766"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference = 'Stop'; $root = $env:HERO_JOURNEY_ROOT; $port = 0; if (-not [int]::TryParse($env:HERO_JOURNEY_PORT, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Port must be between 1 and 65535.' };" ^
 "$url = 'http://127.0.0.1:' + $port + '/'; $projectPath = [IO.Path]::GetFullPath((Join-Path $root 'planning\hero-journey\journey.json')); $health = $null; try { $health = Invoke-RestMethod -Uri ($url + 'api/health') -TimeoutSec 2 } catch {};" ^
 "if ($health -and $health.service -eq 'slime-hero-journey' -and $health.projectPath -eq $projectPath) { Start-Process $url; exit 0 };" ^
 "$probe = New-Object Net.Sockets.TcpClient; try { $connected = $probe.ConnectAsync('127.0.0.1', $port).Wait(700); if ($connected -and $probe.Connected) { throw ('Port ' + $port + ' is already occupied. Use run_hero_journey.cmd 8767.') } } catch [AggregateException] {} finally { $probe.Dispose() };" ^
 "$python = $null; $prefix = ''; $bundled = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'; if (Test-Path -LiteralPath $bundled) { $python = $bundled } else { $py = Get-Command py.exe -ErrorAction SilentlyContinue; if ($py) { $python = $py.Source; $prefix = '-3 ' } else { $py = Get-Command python.exe -ErrorAction SilentlyContinue; if ($py -and $py.Source -notlike '*\WindowsApps\*') { $python = $py.Source } } }; if (-not $python) { throw 'Python 3 was not found. No dependencies were installed.' };" ^
 "$logs = Join-Path $root 'output\hero_journey'; New-Item -ItemType Directory -Path $logs -Force | Out-Null; $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $stdout = Join-Path $logs ($stamp + '-server.stdout.log'); $stderr = Join-Path $logs ($stamp + '-server.stderr.log'); $server = Join-Path $root 'planning\hero-journey\server.py'; $quote = [char]34; $arguments = $prefix + $quote + $server + $quote + ' --port ' + $port;" ^
 "$process = Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru; $process.Id | Set-Content -LiteralPath (Join-Path $logs ('server-' + $port + '.pid'));" ^
 "for ($attempt = 0; $attempt -lt 30; $attempt++) { Start-Sleep -Milliseconds 250; $health = $null; try { $health = Invoke-RestMethod -Uri ($url + 'api/health') -TimeoutSec 1 } catch {}; if ($health -and $health.service -eq 'slime-hero-journey' -and $health.projectPath -eq $projectPath) { Start-Process $url; Write-Host ('Editor opened: ' + $url); exit 0 }; if ($process.HasExited) { break } }; if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr }; throw ('Editor did not start. Logs: ' + $logs)"
if errorlevel 1 (
  echo.
  echo The editor could not start. See the message above.
  pause
  exit /b 1
)
endlocal
