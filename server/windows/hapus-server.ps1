# Menghentikan dan melepas tugas otomatis Server POS (database TIDAK dihapus).
# Jalankan di PowerShell "Run as administrator":  powershell -ExecutionPolicy Bypass -File windows\hapus-server.ps1
$ErrorActionPreference = 'Continue'
foreach ($t in 'POS Server Sinar Okky', 'POS Cadangan Server') {
    Stop-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
}
# Hentikan node server yang masih jalan (Stop-ScheduledTask tidak selalu ikut menghentikannya).
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*src\server.js*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-NetFirewallRule -DisplayName 'POS Server Sinar Okky' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host 'Tugas otomatis server dilepas. Database MySQL dan cadangan tidak dihapus.'
