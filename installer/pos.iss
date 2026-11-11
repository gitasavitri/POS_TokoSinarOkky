; Installer Windows untuk Aplikasi Toko dan Aplikasi Pusat (Inno Setup 6).
; Dibuat otomatis oleh GitHub Actions. Untuk membuat sendiri di PC Windows (setelah `flutter build windows --release`):
;   iscc /DAPP=toko  /DVERSI=1.0.0 installer\pos.iss
;   iscc /DAPP=pusat /DVERSI=1.0.0 installer\pos.iss
; Hasil: installer\hasil\POS-Toko-Setup-<versi>.exe / POS-Pusat-Setup-<versi>.exe
;
; Data (database kasir, cadangan, pengaturan) disimpan di AppData & Documents, BUKAN di folder program,
; jadi update atau uninstall tidak menghapus data toko.

#ifndef APP
  #define APP "toko"
#endif
#ifndef VERSI
  #define VERSI "1.0.0"
#endif

#if APP == "toko"
  #define NamaApp "POS Toko Sinar Okky"
  #define NamaPendek "POS Toko"
  #define Exe "app_toko.exe"
  #define Folder "app_toko"
  #define IdApp "{{6F1C3E2A-4B7D-4E59-9A1F-2C8D5B7E0A11}"
  #define Berkas "POS-Toko-Setup"
#else
  #define NamaApp "POS Pusat Sinar Okky"
  #define NamaPendek "POS Pusat"
  #define Exe "app_pusat.exe"
  #define Folder "app_pusat"
  #define IdApp "{{8A2D4F6B-1C3E-4A7D-B5E9-3F0A6C8D2B22}"
  #define Berkas "POS-Pusat-Setup"
#endif

[Setup]
AppId={#IdApp}
AppName={#NamaApp}
AppVersion={#VERSI}
AppVerName={#NamaApp} {#VERSI}
AppPublisher=Toko Sinar Okky
DefaultDirName={autopf}\{#NamaApp}
DefaultGroupName={#NamaApp}
DisableProgramGroupPage=yes
OutputDir=hasil
OutputBaseFilename={#Berkas}-{#VERSI}
SetupIconFile=..\{#Folder}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#Exe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; Aplikasi yang sedang terbuka ditutup dulu saat update.
CloseApplications=force
RestartApplications=no
VersionInfoVersion={#VERSI}
VersionInfoProductName={#NamaApp}

[Languages]
; Bahasa Indonesia bukan bawaan Inno Setup; tombol wizard memakai bahasa Inggris, teks pilihan di bawah sudah Indonesia.
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktop"; Description: "Buat ikon di Desktop"; GroupDescription: "Ikon:"
#if APP == "toko"
Name: "otomatis"; Description: "Buka {#NamaPendek} otomatis setelah Windows menyala (untuk PC kasir)"; GroupDescription: "Lainnya:"; Flags: unchecked
#endif

[Files]
; Semua isi hasil build (exe, dll, folder data). Runtime Visual C++ sudah disalin ke folder ini oleh CI.
Source: "..\{#Folder}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#NamaApp}"; Filename: "{app}\{#Exe}"
Name: "{group}\Hapus {#NamaApp}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#NamaPendek}"; Filename: "{app}\{#Exe}"; Tasks: desktop
#if APP == "toko"
Name: "{commonstartup}\{#NamaPendek}"; Filename: "{app}\{#Exe}"; Tasks: otomatis
#endif

[Run]
Filename: "{app}\{#Exe}"; Description: "Buka {#NamaPendek} sekarang"; Flags: nowait postinstall skipifsilent
