; ============================================================
; MexOrbit - instalador de Windows (Inno Setup 6)
;
; No se compila a mano: lo invoca tools/build-windows.ps1, que le pasa la
; version y la carpeta del export de Godot. Compilarlo suelto usa los valores
; por defecto de abajo y sirve para probar el asistente.
;
; La decision que manda en este archivo es PrivilegesRequired=lowest. Ver la
; seccion "Instalador de Windows" del README para el porque.
; ============================================================

#define AppName       "MexOrbit"
#define AppPublisher  "MexOrbit"
#define AppURL        "https://astrion.turname.mx"
#define AppExe        "MexOrbit.exe"

; La version la inyecta el build con /DAppVersion=x.y.z
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

; Carpeta con lo que exporto Godot (MexOrbit.exe + MexOrbit.pck)
#ifndef SourceDir
  #define SourceDir "..\build\windows"
#endif

[Setup]
; El AppId NO se cambia JAMAS: es lo que ata una instalacion con su
; actualizacion. Si cambia, Windows trata la version nueva como otro programa
; y el jugador termina con dos MexOrbit instalados.
AppId={{2D64FAB1-0A11-4B5F-B0BB-84F5847B1AE3}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
VersionInfoVersion={#AppVersion}

; ---- lo que evita el boton escondido ----
; `lowest` = el instalador NO pide elevacion, asi que no sale el escudo de UAC
; ("Quieres permitir que esta aplicacion haga cambios?"), que es el segundo
; dialogo donde la gente se atora. A cambio no se puede escribir en
; "Program Files", y por eso se instala por USUARIO en:
;   %LOCALAPPDATA%\Programs\MexOrbit
; Es el mismo sitio y el mismo patron que usa VS Code.
;
; OJO: esto NO quita el aviso de SmartScreen. Ese depende de la FIRMA, no del
; instalador. Sin certificado sale igual; con certificado OV se va apagando
; conforme el certificado gana reputacion.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}

; Menos pantallas = menos sitios donde dudar. Se deja la de carpeta por si
; alguien quiere otro disco, pero el grupo del menu inicio no lo elige nadie.
DisableProgramGroupPage=yes
DisableReadyPage=no
WizardStyle=modern
ShowLanguageDialog=auto

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; lzma2/max sobre ~90 MB de pck tarda un poco mas en comprimir pero baja
; bastante lo que el jugador descarga. SolidCompression ayuda porque el pck y
; el exe comparten poco, pero los assets dentro del pck si repiten.
Compression=lzma2/max
SolidCompression=yes

OutputDir=..\build\installer
OutputBaseFilename={#AppName}-Setup-{#AppVersion}
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

; Si el juego esta abierto durante una actualizacion, el Restart Manager lo
; cierra en vez de fallar con "archivo en uso".
CloseApplications=yes
RestartApplications=no

; Cuando haya icono propio, descomentar (ver el pendiente en el README):
; SetupIconFile=..\assets\ui\icon.ico

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Se copia la carpeta entera del export y no una lista de archivos a mano:
; Godot puede emitir DLLs extra (ANGLE, D3D12) segun las opciones del preset, y
; una lista fija se queda corta en silencio el dia que se enciendan.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";              Filename: "{app}\{#AppExe}"
Name: "{group}\Desinstalar {#AppName}";  Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";        Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

; No hay [UninstallDelete]: la partida y la configuracion viven en `user://`
; (%APPDATA%\Godot\app_userdata\MexOrbit), fuera de {app}. Desinstalar no debe
; borrar eso - quien reinstala espera encontrar sus cosas.
