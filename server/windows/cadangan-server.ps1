# Cadangan database Server POS (MySQL) ke file .zip. Dipanggil Task Scheduler tiap hari
# (tugas "POS Cadangan Server"), bisa juga dijalankan manual:
#   powershell -ExecutionPolicy Bypass -File server\windows\cadangan-server.ps1
# Hasil: <folder cadangan>\pos_pusat-YYYYMMDD-HHmm.zip, yang lebih dari 30 file dihapus otomatis.
# Folder cadangan: isi CADANGAN_FOLDER di .env (mis. D:\POS-Cadangan-Server atau flashdisk E:\POS-Cadangan-Server).
param([string]$Folder)
$ErrorActionPreference = 'Stop'
$folderServer = Split-Path -Parent $PSScriptRoot

# Baca .env
$env_ = @{}
Get-Content (Join-Path $folderServer '.env') | ForEach-Object {
    if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)\s*$') { $env_[$Matches[1]] = $Matches[2] }
}
if (-not $Folder) { $Folder = $env_['CADANGAN_FOLDER'] }
if (-not $Folder) { $Folder = 'C:\POS-Cadangan-Server' }
New-Item -ItemType Directory -Force -Path $Folder | Out-Null

# DATABASE_URL=mysql://pengguna:sandi@host:port/nama_database
$u = [Uri]$env_['DATABASE_URL']
$info = $u.UserInfo.Split(':', 2)
$pengguna = [Uri]::UnescapeDataString($info[0])
$sandi = [Uri]::UnescapeDataString($info[1])
$port = if ($u.Port -gt 0) { $u.Port } else { 3306 }
$namaDb = $u.AbsolutePath.TrimStart('/')

$mysqldump = (Get-Command mysqldump -ErrorAction SilentlyContinue).Source
if (-not $mysqldump) {
    $mysqldump = Get-ChildItem "$env:ProgramFiles\MySQL\MySQL Server *\bin\mysqldump.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $mysqldump) { throw 'mysqldump.exe tidak ditemukan. Pastikan MySQL Server 8 terpasang.' }

$waktu = Get-Date -Format 'yyyyMMdd-HHmm'
$sql = Join-Path $env:TEMP "pos_pusat-$waktu.sql"
$zip = Join-Path $Folder "pos_pusat-$waktu.zip"
# Sandi ditulis ke file sementara (bukan di baris perintah) lalu langsung dihapus.
$cnf = Join-Path $env:TEMP "pos-cadangan-$([guid]::NewGuid()).cnf"
Set-Content -Path $cnf -Encoding ascii -Value "[client]`nuser=$pengguna`npassword=$sandi`nhost=$($u.Host)`nport=$port"
try {
    & $mysqldump "--defaults-extra-file=$cnf" --single-transaction --routines --triggers --no-tablespaces `
        --default-character-set=utf8mb4 "--result-file=$sql" $namaDb
    if ($LASTEXITCODE -ne 0) { throw "mysqldump gagal (kode $LASTEXITCODE)" }
} finally {
    Remove-Item -Force $cnf -ErrorAction SilentlyContinue
}
Compress-Archive -Path $sql -DestinationPath $zip -Force
Remove-Item -Force $sql

# Simpan 30 cadangan terbaru saja
Get-ChildItem $Folder -Filter 'pos_pusat-*.zip' | Sort-Object Name -Descending | Select-Object -Skip 30 | Remove-Item -Force
Write-Output "Cadangan server tersimpan: $zip"
