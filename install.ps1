# ==============================================================================
# OpenMoney - Instalador Automatizado para Windows (PowerShell)
# Repositório Oficial: https://github.com/FSF77/openmoney-new
# Execução direta:
#   irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex
# ==============================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ErrorActionPreference = "Stop"

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  🚀 Instalador do OpenMoney para Windows           " -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# 1. Fechar o OpenMoney se estiver em execução para evitar bloqueio de arquivos
$running = Get-Process -Name "openmoney" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "⚠️  Fechando aplicativo OpenMoney em execução..." -ForegroundColor Yellow
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 2. Consultar version.json com cache-busting
Write-Host "📡 Consultando versão mais recente..." -ForegroundColor Yellow
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$versionUrl = "https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json?t=$timestamp"

try {
    $versionJson = Invoke-RestMethod -Uri $versionUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -UseBasicParsing
} catch {
    Write-Error "❌ Falha ao consultar informações de versão: $_"
    exit 1
}

$downloadUrl = ""
$version = ""

if ($versionJson.windows) {
    $downloadUrl = $versionJson.windows.downloadUrl
    $version = $versionJson.windows.version
}
if (-not $downloadUrl) {
    $downloadUrl = $versionJson.downloadUrl
    $version = $versionJson.version
}

if (-not $downloadUrl) {
    Write-Error "❌ URL de download para Windows não encontrada no arquivo de versão."
    exit 1
}

# 3. Definir diretório de instalação (%LOCALAPPDATA%\Programs\OpenMoney)
$installDir = Join-Path $env:LOCALAPPDATA "Programs\OpenMoney"
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

$tempDir = Join-Path $env:TEMP ("openmoney-install-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$zipPath = Join-Path $tempDir "OpenMoney-Windows.zip"

try {
    # 4. Baixar o pacote
    Write-Host "📦 Baixando OpenMoney v$version..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

    # 5. Descompactar os arquivos
    Write-Host "📂 Extraindo arquivos para $installDir..." -ForegroundColor Yellow
    $extractDir = Join-Path $tempDir "extracted"
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # Copiar recursivamente os arquivos extraídos para o diretório de instalação
    Copy-Item -Path "$extractDir\*" -Destination $installDir -Recurse -Force

    # 6. Criar Atalho no Menu Iniciar
    $startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $wscript = New-Object -ComObject WScript.Shell
    $shortcutPath = Join-Path $startMenuDir "OpenMoney.lnk"
    $shortcut = $wscript.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $installDir "openmoney.exe"
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = "OpenMoney - Sistema Financeiro Pessoal"
    $shortcut.Save()

    # 7. Criar Atalho na Área de Trabalho (Desktop)
    $desktopDir = [System.Environment]::GetFolderPath("Desktop")
    if (Test-Path $desktopDir) {
        $desktopShortcutPath = Join-Path $desktopDir "OpenMoney.lnk"
        $shortcutDesk = $wscript.CreateShortcut($desktopShortcutPath)
        $shortcutDesk.TargetPath = Join-Path $installDir "openmoney.exe"
        $shortcutDesk.WorkingDirectory = $installDir
        $shortcutDesk.Description = "OpenMoney - Sistema Financeiro Pessoal"
        $shortcutDesk.Save()
    }

    Write-Host ""
    Write-Host "✅ OpenMoney v$version instalado com sucesso!" -ForegroundColor Green
    Write-Host "📂 Local: $installDir" -ForegroundColor Gray
    Write-Host "🚀 Abrindo aplicativo..." -ForegroundColor Cyan

    # 8. Iniciar o OpenMoney
    Start-Process (Join-Path $installDir "openmoney.exe")
} finally {
    # 9. Limpeza de arquivos temporários
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
