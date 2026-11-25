# Menjalankan Server POS terus-menerus di PC Windows toko.
# Dipanggil otomatis oleh Task Scheduler (tugas "POS Server Sinar Okky") saat PC menyala.
# Kalau server berhenti (mis. MySQL belum siap saat PC baru menyala), dicoba lagi tiap 10 detik.
$ErrorActionPreference = 'Continue'
$folderServer = Split-Path -Parent $PSScriptRoot
$folderLog = Join-Path $folderServer 'log'
New-Item -ItemType Directory -Force -Path $folderLog | Out-Null
$log = Join-Path $folderLog 'server.log'

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = Join-Path $env:ProgramFiles 'nodejs\node.exe' }

Set-Location $folderServer
function Catat($teks) { [IO.File]::AppendAllText($log, "==== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $teks`r`n") }
while ($true) {
    # Log dibatasi 10 MB: yang lama disimpan sebagai server.log.lama
    if ((Test-Path $log) -and ((Get-Item $log).Length -gt 10MB)) {
        Move-Item -Force $log (Join-Path $folderLog 'server.log.lama')
    }
    Catat 'server dinyalakan'
    # Lewat cmd supaya log tetap UTF-8 (Windows PowerShell 5 menulis redirect sebagai UTF-16).
    & cmd.exe /d /c "`"$node`" src\server.js >> `"$log`" 2>&1"
    Catat "server berhenti (kode $LASTEXITCODE), dicoba lagi 10 detik lagi"
    Start-Sleep -Seconds 10
}
