# Levanta el entorno de desarrollo completo y lanza el cliente con ventana.
#
# Comprueba y arranca lo que falte: MySQL de dev (3307), api (5100) y game
# server (5200); cierra cualquier Godot previo y abre el cliente maximizado.
#
# Uso:  .\tools\dev-run.ps1              (todo y lanza el cliente)
#       .\tools\dev-run.ps1 -SoloServicios   (deja los servicios listos, sin cliente)
#       .\tools\dev-run.ps1 -Autotest        (pasada e2e completa del loop, ~3 min)
#       .\tools\dev-run.ps1 -Bestiario       (solo los retratos de los NPC, ~20 s)
#       .\tools\dev-run.ps1 -Bestiario -Calidad baja   (los mismos, forzando un nivel)
#       .\tools\dev-run.ps1 -Detener         (apaga api y game server)
param(
    [switch]$SoloServicios,
    [switch]$Autotest,
    [switch]$Bestiario,
    [ValidateSet('', 'baja', 'media', 'alta')][string]$Calidad = '',
    [switch]$Detener
)

$ErrorActionPreference = 'Stop'
$cliente = Split-Path -Parent $PSScriptRoot
$v1 = Split-Path -Parent $cliente
$api = Join-Path $v1 'mex-orbit-api\src\MexOrbit.Api'
$server = Join-Path $v1 'mex-orbit-game-server\src\MexOrbit.GameServer'
$mysqlTools = Join-Path $v1 'mex-orbit-data-base\tools'

function Puerto-Vivo([int]$puerto) {
    return $null -ne (Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue)
}

function Detener-Puerto([int]$puerto) {
    Get-NetTCPConnection -LocalPort $puerto -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force -Confirm:$false -ErrorAction SilentlyContinue }
}

if ($Detener) {
    Detener-Puerto 5100
    Detener-Puerto 5200
    Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } |
        Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'Cliente, api y game server detenidos (el MySQL de dev sigue arriba).'
    exit 0
}

# ---- 0. credenciales de dev ----
# dev_login.cfg no se versiona; si falta, se siembra desde la plantilla para
# que el login del cliente siempre venga precargado.
$cfg = Join-Path $cliente 'dev_login.cfg'
if (-not (Test-Path $cfg)) {
    Copy-Item (Join-Path $cliente 'dev_login.cfg.example') $cfg
    Write-Host 'dev_login.cfg creado desde la plantilla (odrack).'
}

# ---- 1. MySQL de dev ----
if (-not (Puerto-Vivo 3307)) {
    Write-Host 'MySQL de dev apagado: arrancando...'
    & (Join-Path $mysqlTools 'dev-mysql.ps1')
    Start-Sleep -Seconds 5
}
Write-Host 'MySQL de dev (3307): OK'

# ---- 2. api ----
if (-not (Puerto-Vivo 5100)) {
    Write-Host 'api apagada: compilando y arrancando...'
    Push-Location $api
    dotnet build --nologo -v q | Out-Null
    Start-Process dotnet -ArgumentList 'run', '--no-build' -WindowStyle Hidden
    Pop-Location
    Start-Sleep -Seconds 6
}
Write-Host 'api (5100): OK'

# ---- 3. game server ----
if (-not (Puerto-Vivo 5200)) {
    Write-Host 'game server apagado: compilando y arrancando...'
    Push-Location $server
    dotnet build --nologo -v q | Out-Null
    Start-Process dotnet -ArgumentList 'run', '--no-build' -WindowStyle Hidden
    Pop-Location
    Start-Sleep -Seconds 7
}
Write-Host 'game server (5200): OK'

if ($SoloServicios) {
    Write-Host 'Servicios listos.'
    exit 0
}

# ---- 4. el cliente ----
Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } |
    Stop-Process -Force -Confirm:$false -ErrorAction SilentlyContinue

# Godot solo registra un class_name nuevo tras escanear el proyecto: sin este
# paso, un script recien creado revienta con "Could not find type".
Push-Location $cliente
godot --headless --path . --import 2>&1 | Out-Null
Pop-Location
Write-Host 'clases globales: OK'

if ($Autotest -or $Bestiario) {
    # ambas pruebas usan la cuenta TestBot; una sesion por cuenta, asi que no
    # deben correr mientras el usuario juega con ella
    $captura = 'C:/Tools/autotest.png'
    # El BESTIARIO solo retrata a cada bicho y sale: es la prueba para trabajo de
    # arte, donde la pasada completa del loop es un peaje de tres minutos.
    $modo = if ($Bestiario) { 'bestiario' } else { 'loop' }
    # Holgado sobre el limite interno de cada modo (60 s / 190 s): si el lanzador
    # mata a Godot antes, el resultado es un timeout falso que no dice nada.
    $tope = if ($Bestiario) { 90000 } else { 300000 }
    Push-Location $cliente
    $argumentos = @('--path', '.', '--', "--screenshot=$captura", "--modo=$modo")
    if ($Calidad) { $argumentos += "--calidad=$Calidad" }
    $p = Start-Process godot -ArgumentList $argumentos -NoNewWindow -PassThru
    if (-not $p.WaitForExit($tope)) {
        $p | Stop-Process -Force
        Write-Host "$($modo.ToUpper()): timeout"
    }
    Pop-Location
    Write-Host "Prueba '$modo' terminada. Capturas junto a: $captura"
    exit 0
}

Push-Location $cliente
Start-Process godot -ArgumentList '--path', '.'
Pop-Location
Write-Host 'Cliente lanzado (entra con las credenciales de dev_login.cfg).'
