param([switch]$Play, [switch]$ServerOnly, [string]$GodotPath = '', [string]$PythonPath = '')
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if (-not $PythonPath) {
    $bundledPython = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (Test-Path -LiteralPath $bundledPython) { $PythonPath = $bundledPython }
    else { $PythonPath = (Get-Command python -ErrorAction Stop).Source }
}
if (-not $ServerOnly -and -not $GodotPath) {
    $GodotPath = (& $PythonPath (Join-Path $PSScriptRoot 'tools/godot_runtime.py')).Trim()
}
if (-not $ServerOnly -and -not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot was not found. Pass -GodotPath with your installation path.' }
$health = $null
try { $health = Invoke-RestMethod 'http://127.0.0.1:7556/dev-health' -TimeoutSec 2 } catch {}
if ($health -and $health.service -ne 'fogchess-godot-development') { throw 'Port 7556 belongs to another service.' }
if (-not $health) {
    if (Get-NetTCPConnection -LocalPort 7556 -State Listen -ErrorAction SilentlyContinue) { throw 'Port 7556 is already occupied.' }
    New-Item -ItemType Directory -Force .dev-data | Out-Null
    # Use the existing per-user encrypted key only in the child server environment.
    # Never pass it on the command line, write plaintext, or change the saved key.
    $injectedAdminKey = $false
    $encryptedAdminPath = Join-Path $PSScriptRoot '.dev-data/security/admin-key.dpapi'
    try {
        if (-not $env:FOG_ADMIN_KEY -and (Test-Path -LiteralPath $encryptedAdminPath)) {
            $protectedAdminKey = ([IO.File]::ReadAllText($encryptedAdminPath)).Trim() | ConvertTo-SecureString
            $adminKeyPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($protectedAdminKey)
            try {
                $env:FOG_ADMIN_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminKeyPointer)
                $injectedAdminKey = $true
            } finally {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminKeyPointer)
                $protectedAdminKey.Dispose()
            }
        }
        $process = Start-Process -FilePath $PythonPath -ArgumentList '-u dev_server.py' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput '.dev-data\server.log' -RedirectStandardError '.dev-data\server-error.log'
    } finally {
        if ($injectedAdminKey) { Remove-Item Env:FOG_ADMIN_KEY -ErrorAction SilentlyContinue }
    }
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
