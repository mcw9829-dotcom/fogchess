param([switch]$Play, [switch]$ServerOnly, [string]$GodotPath = '', [string]$PythonPath = '')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not $PythonPath) {
    $bundledPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundledPython) { $PythonPath = $bundledPython }
    else { $PythonPath = (Get-Command python -ErrorAction Stop).Source }
}
if (-not $ServerOnly -and -not $GodotPath) {
    $GodotPath = (& $PythonPath (Join-Path $PSScriptRoot 'godot_runtime.py')).Trim()
}
if (-not $ServerOnly -and -not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot was not found. Pass -GodotPath with your installation path.' }
$health = $null
try { $health = Invoke-RestMethod 'http://127.0.0.1:7556/dev-health' -TimeoutSec 2 } catch {}
if ($health -and $health.service -ne 'fogchess-godot-development') { throw 'Port 7556 belongs to another service.' }
if (-not $health) {
    if (Get-NetTCPConnection -LocalPort 7556 -State Listen -ErrorAction SilentlyContinue) { throw 'Port 7556 is already occupied.' }
    New-Item -ItemType Directory -Force .dev-data | Out-Null
    $process = Start-Process -FilePath $PythonPath -ArgumentList '-u dev_server.py' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput '.dev-data\server.log' -RedirectStandardError '.dev-data\server-error.log'
    $process.Id | Set-Content '.dev-data\server.pid'
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 200
        try { $health = Invoke-RestMethod 'http://127.0.0.1:7556/dev-health' -TimeoutSec 1; break } catch {}
        if ($process.HasExited) { throw 'Development server exited. See .dev-data/server-error.log.' }
    }
    if (-not $health) { throw 'Development server did not become ready. See .dev-data/server-error.log.' }
}
$arguments = '--path godot'
if (-not $Play) { $arguments += ' --editor' }
if (-not $ServerOnly) { Start-Process -FilePath $GodotPath -ArgumentList $arguments -WorkingDirectory $PSScriptRoot -WindowStyle Normal }
Write-Host 'Development server ready at http://127.0.0.1:7556. Press F5 in Godot to play.'
