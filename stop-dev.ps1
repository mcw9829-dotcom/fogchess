$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $PSScriptRoot '.dev-data\server.pid'
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Host 'No managed development server PID found.'; exit }
$serverPid = [int](Get-Content -LiteralPath $pidFile)
$process = Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid"
if ($process -and $process.Name -like 'python*' -and $process.CommandLine -match 'dev_server\.py') {
    Stop-Process -Id $serverPid
    Remove-Item -LiteralPath $pidFile
    Write-Host 'Development server stopped.'
} elseif ($process) { throw 'PID belongs to a different process; nothing was stopped.' }
else { Write-Host 'Development server is already stopped.' }
