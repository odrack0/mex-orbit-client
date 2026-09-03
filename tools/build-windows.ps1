# ============================================================
# Construye el cliente de Windows y su instalador.
#
#   .\tools\build-windows.ps1                      # exporta y arma el instalador
#   .\tools\build-windows.ps1 -Version 0.2.0       # con otra version
#   .\tools\build-windows.ps1 -SkipExport          # solo re-arma el instalador
#   .\tools\build-windows.ps1 -Sign -CertThumbprint ABC123...
#
# Sale en build/installer/MexOrbit-Setup-<version>.exe
#
# Sin acentos a proposito: PowerShell 5.1 lee un .ps1 sin BOM como ANSI y
# convierte cualquier acento en basura.
# ============================================================
[CmdletBinding()]
param(
    [string] $Version        = '0.1.0',
    [switch] $SkipExport,
    [switch] $Sign,
    [string] $CertThumbprint = '',
    [string] $TimestampUrl   = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'

# Firma Authenticode con el signtool del Windows SDK. `/tr` es el sellado de
# tiempo RFC3161: sin el, la firma deja de valer el dia que caduque el
# certificado y los instaladores ya repartidos empiezan a dar aviso solos.
function Invoke-Firma {
    param(
        [Parameter(Mandatory)] [string] $Archivo,
        [Parameter(Mandatory)] [string] $Thumbprint,
        [Parameter(Mandatory)] [string] $Timestamp
    )
    $patron = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe"
    $signtool = Get-ChildItem $patron -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $signtool) { throw 'no se encontro signtool.exe (instala el Windows SDK)' }

    Write-Host ('firmando {0}...' -f (Split-Path -Leaf $Archivo))
    & $signtool.FullName sign /sha1 $Thumbprint /fd SHA256 /tr $Timestamp /td SHA256 /q $Archivo
    if ($LASTEXITCODE -ne 0) { throw "signtool fallo con codigo $LASTEXITCODE" }
}

$raiz = Split-Path -Parent $PSScriptRoot
Push-Location $raiz
try {
    $salidaExport = Join-Path $raiz 'build\windows'
    $salidaSetup  = Join-Path $raiz 'build\installer'
    $exe          = Join-Path $salidaExport 'MexOrbit.exe'
    $pck          = Join-Path $salidaExport 'MexOrbit.pck'

    # ---- 1. herramientas ----
    # Se comprueban ANTES de nada: un build que falla a la mitad deja la carpeta
    # con el export viejo y da la impresion de haber funcionado.
    $godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
    if (-not $godot) { throw "no hay 'godot' en el PATH" }

    $iscc = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) {
        throw 'no se encontro ISCC.exe (Inno Setup 6): https://jrsoftware.org/isdl.php'
    }

    # ---- 2. exportar ----
    if (-not $SkipExport) {
        New-Item -ItemType Directory -Force $salidaExport | Out-Null
        Get-ChildItem $salidaExport -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        # Godot solo registra un class_name nuevo tras escanear el proyecto.
        Write-Host 'importando...'
        & $godot --headless --path . --import 2>&1 | Out-Null

        Write-Host 'exportando Windows Desktop...'
        $logExport = & $godot --headless --path . --export-release 'Windows Desktop' $exe 2>&1

        # `--export-release` puede devolver 0 y aun asi no escribir nada, asi que
        # lo que se comprueba es el ARCHIVO, no el codigo de salida.
        foreach ($obligatorio in @($exe, $pck)) {
            if ((-not (Test-Path $obligatorio)) -or ((Get-Item $obligatorio).Length -eq 0)) {
                Write-Host ($logExport -join [Environment]::NewLine)
                throw ('EXPORT FALLO: no se genero {0}' -f (Split-Path -Leaf $obligatorio))
            }
        }
    }

    # ---- 3. guardian de credenciales ----
    # dev_login.cfg lleva credenciales reales. El preset lo excluye, pero un
    # preset se edita y este paquete se REPARTE.
    #
    # Las agujas son la FIRMA DEL CONTENIDO del cfg, no su nombre. Buscar la
    # palabra "dev_login" da FALSO POSITIVO: data/config/net.json guarda la RUTA
    # al archivo (clave `dev_login_path`) y los JSON viajan verbatim dentro del
    # pck. Medido sobre el pck real: "[login]", "password =" y "dev1234" estan
    # ausentes; "username" si aparece (lo usa la pantalla de login) y por eso no
    # sirve como aguja.
    if (-not (Test-Path $pck)) { throw "no hay pck que revisar en $pck" }
    # Se lee UNA vez (el pck pasa de 90 MB) y con ISO-8859-1, que mapea cada
    # byte a un caracter sin perder ninguno. `Encoding::Latin1` por nombre no
    # existe en .NET Framework, que es quien corre PowerShell 5.1.
    $comoTexto = [System.IO.File]::ReadAllText($pck, [System.Text.Encoding]::GetEncoding(28591))
    foreach ($aguja in @('\[login\]', 'password\s*=', 'dev1234')) {
        if ($comoTexto -match $aguja) {
            throw "ABORTADO: el paquete contiene '$aguja' (credenciales dentro)"
        }
    }
    $comoTexto = $null
    Write-Host 'paquete limpio: sin credenciales dentro'

    # ---- 4. firmar el exe del juego ----
    # Primero el exe y luego el instalador: SmartScreen mira el instalador
    # descargado, pero el antivirus y los arranques posteriores miran el exe de
    # dentro. Firmar solo uno deja la mitad del problema.
    if ($Sign) {
        if (-not $CertThumbprint) { throw '-Sign requiere -CertThumbprint' }
        Invoke-Firma -Archivo $exe -Thumbprint $CertThumbprint -Timestamp $TimestampUrl
    }

    # ---- 5. instalador ----
    New-Item -ItemType Directory -Force $salidaSetup | Out-Null
    $iss = Join-Path $PSScriptRoot 'mexorbit.iss'
    Write-Host 'compilando el instalador...'
    & $iscc "/DAppVersion=$Version" "/DSourceDir=$salidaExport" $iss | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ISCC fallo con codigo $LASTEXITCODE" }

    $setup = Join-Path $salidaSetup "MexOrbit-Setup-$Version.exe"
    if (-not (Test-Path $setup)) { throw "el instalador no aparecio en $setup" }

    if ($Sign) { Invoke-Firma -Archivo $setup -Thumbprint $CertThumbprint -Timestamp $TimestampUrl }

    # ---- 6. reporte ----
    $mbSetup  = [math]::Round((Get-Item $setup).Length / 1MB, 1)
    $mbExport = [math]::Round((Get-ChildItem $salidaExport -Recurse |
        Measure-Object Length -Sum).Sum / 1MB, 1)
    Write-Host ''
    Write-Host "BUILD OK  $setup"
    Write-Host "  export:      $mbExport MB"
    Write-Host "  instalador:  $mbSetup MB"
    if (-not $Sign) { Write-Host '  SIN FIRMAR: SmartScreen va a avisar al descargarlo.' }
}
finally { Pop-Location }
