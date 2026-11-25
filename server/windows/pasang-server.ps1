# Memasang Server POS di PC Windows toko supaya menyala otomatis.
# Jalankan SEKALI di PowerShell "Run as administrator", dari folder server:
#   powershell -ExecutionPolicy Bypass -File windows\pasang-server.ps1
# Yang dilakukan:
#   1. Cek Node.js, isi .env, pasang paket (npm ci), migrasi database
#   2. Tugas "POS Server Sinar Okky": server menyala sendiri setiap PC dinyalakan (walau belum ada yang login)
#   3. Tugas "POS Cadangan Server": cadangan database setiap hari jam 21:30
#   4. Firewall: buka port server untuk jaringan lokal toko (PC kasir kedua nanti)
$ErrorActionPreference = 'Stop'
$folderServer = Split-Path -Parent $PSScriptRoot
Set-Location $folderServer

function Langkah($teks) { Write-Host "`n== $teks" -ForegroundColor Cyan }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Buka PowerShell dengan klik kanan -> "Run as administrator", lalu jalankan lagi.' }

Langkah 'Cek Node.js'
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw 'Node.js belum terpasang. Pasang versi LTS dari https://nodejs.org lalu jalankan lagi.' }
$versi = (& $node --version).TrimStart('v').Split('.')[0]
if ([int]$versi -lt 20) { throw "Node.js minimal versi 20 (sekarang $(& $node --version))." }
Write-Host "Node.js $(& $node --version)"

Langkah 'Isi pengaturan (.env)'
$fileEnv = Join-Path $folderServer '.env'
if (-not (Test-Path $fileEnv)) {
    Copy-Item (Join-Path $folderServer '.env.contoh') $fileEnv
    # Server di PC toko: bisa diakses PC kasir lain di jaringan toko.
    (Get-Content $fileEnv) -replace '^HOST=.*', 'HOST=0.0.0.0' | Set-Content $fileEnv
    Write-Host ".env dibuat. Buka dengan Notepad, ubah DATABASE_URL (sandi MySQL), simpan, lalu jalankan skrip ini lagi." -ForegroundColor Yellow
    notepad $fileEnv
    exit 1
}
$isiEnv = Get-Content $fileEnv -Raw
if ($isiEnv -match 'ganti-sandi') { throw 'DATABASE_URL di .env masih berisi "ganti-sandi". Isi sandi MySQL yang benar dulu.' }
$port = if ($isiEnv -match '(?m)^PORT=(\d+)') { [int]$Matches[1] } else { 3000 }

Langkah 'Pasang paket server (npm ci)'
& npm ci --omit=dev
if ($LASTEXITCODE -ne 0) { throw 'npm ci gagal. Cek koneksi internet.' }

Langkah 'Migrasi database'
& npm run migrasi
if ($LASTEXITCODE -ne 0) { throw 'Migrasi gagal. Cek DATABASE_URL di .env dan pastikan MySQL menyala.' }

Langkah 'Tugas otomatis: server menyala saat PC menyala'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$akun = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$atur = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
$aksiServer = New-ScheduledTaskAction -Execute $ps -WorkingDirectory $folderServer `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$folderServer\windows\jalankan-server.ps1`""
Register-ScheduledTask -TaskName 'POS Server Sinar Okky' -Action $aksiServer -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Principal $akun -Settings $atur -Description 'Server POS Toko Sinar Okky (Node.js). Log: server\log\server.log' -Force | Out-Null

Langkah 'Tugas otomatis: cadangan database tiap hari 21:30'
$aturCadangan = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$aksiCadangan = New-ScheduledTaskAction -Execute $ps -WorkingDirectory $folderServer `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$folderServer\windows\cadangan-server.ps1`""
Register-ScheduledTask -TaskName 'POS Cadangan Server' -Action $aksiCadangan -Trigger (New-ScheduledTaskTrigger -Daily -At '21:30') `
    -Principal $akun -Settings $aturCadangan -Description 'Cadangan database Server POS (StartWhenAvailable: kalau PC mati jam 21:30, jalan saat PC menyala)' -Force | Out-Null

Langkah "Firewall: buka port $port untuk jaringan lokal (Private)"
Get-NetFirewallRule -DisplayName 'POS Server Sinar Okky' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName 'POS Server Sinar Okky' -Direction Inbound -Protocol TCP -LocalPort $port `
    -Profile Private -Action Allow | Out-Null

Langkah 'Menyalakan server sekarang'
Stop-ScheduledTask -TaskName 'POS Server Sinar Okky' -ErrorAction SilentlyContinue
# Server lama (kalau skrip ini dijalankan ulang) dihentikan dulu supaya port tidak bentrok.
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*src\server.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-ScheduledTask -TaskName 'POS Server Sinar Okky'
$ok = $false
for ($i = 0; $i -lt 30 -and -not $ok; $i++) {
    Start-Sleep -Seconds 1
    try { $ok = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/api/sehat" -TimeoutSec 2).StatusCode -eq 200 } catch {}
}
if ($ok) {
    Write-Host "`nSelesai. Server menyala di http://localhost:$port dan akan menyala sendiri setiap PC dinyalakan." -ForegroundColor Green
    $ip = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254*' } | Select-Object -First 1 -ExpandProperty IPAddress
    if ($ip) { Write-Host "Alamat untuk PC kasir lain di jaringan toko: http://${ip}:$port" }
} else {
    Write-Host "`nServer belum menjawab. Lihat log: $folderServer\log\server.log" -ForegroundColor Yellow
}
