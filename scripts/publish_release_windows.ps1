# ==============================================================================
# OpenMoney Flutter - Script de Compilação e Publicação para Windows (PowerShell)
# Repositório de Releases: https://github.com/FSF77/openmoney-releases
# ==============================================================================

param (
    [string]$CustomNotes = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

# 1. Extrai versão do pubspec.yaml
$PubspecContent = Get-Content "$RootDir\pubspec.yaml"
$VersionLine = $PubspecContent | Select-String -Pattern "^version:\s*([0-9\.]+)\+?([0-9]*)" | Select-Object -First 1

if ($VersionLine -match "version:\s*([0-9\.]+)\+?([0-9]*)") {
    $Version = $Matches[1]
    $BuildNum = if ($Matches[2]) { $Matches[2] } else { "1" }
} else {
    $Version = "2.0.0"
    $BuildNum = "1"
}

$Notes = if ($CustomNotes) { $CustomNotes } else { "OpenMoney Flutter v$Version para Windows - Versão oficial multiplataforma." }
$ReleaseDate = Get-Date -Format "dd/MM/yyyy"

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  🚀 OpenMoney Flutter Windows — Build & Publish v$Version+$BuildNum" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

# 2. Compilação do Windows Release
Write-Host "🔨 Compilando aplicativo Windows em modo Release..." -ForegroundColor Yellow
& flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Falha na compilação do Flutter Windows."
    exit 1
}

$ReleaseDir = "$RootDir\build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    # Tenta caminho alternativo sem x64 dependendo da versão do Flutter
    $ReleaseDir = "$RootDir\build\windows\runner\Release"
}

if (-not (Test-Path "$ReleaseDir\openmoney.exe")) {
    Write-Error "❌ Erro: Executável não encontrado em $ReleaseDir\openmoney.exe"
    exit 1
}

$DistDir = "$RootDir\dist\flutter\windows"
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

$ZipName = "OpenMoney-Windows-$Version.zip"
$ZipPath = "$DistDir\$ZipName"
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Write-Host "📦 Compactando $ZipName..." -ForegroundColor Yellow
# Compacta todos os arquivos e pastas da pasta Release
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -Force

$FileHash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLower()
$FileSizeMb = [math]::Round(((Get-Item $ZipPath).Length / 1MB))

Write-Host "✅ Pacote gerado com sucesso: $ZipPath" -ForegroundColor Green
Write-Host "   Tamanho: ~$FileSizeMb MB"
Write-Host "   SHA256:  $FileHash"

# 3. Publicação no repositório openmoney-releases
$ReleasesRepo = "https://github.com/FSF77/openmoney-releases.git"
$StagingDir = "$env:TEMP\openmoney-releases-staging-$([guid]::NewGuid().ToString().Substring(0,8))"
if (Test-Path $StagingDir) {
    Remove-Item -Recurse -Force $StagingDir
}

Write-Host "📡 Clonando repositório de distribuição: $ReleasesRepo..." -ForegroundColor Yellow
& git clone $ReleasesRepo $StagingDir
if ($LASTEXITCODE -ne 0) {
    Write-Error "❌ Falha ao clonar repositório de releases."
    exit 1
}

$DownloadFlutterWinDir = "$StagingDir\downloads\flutter\windows"
if (-not (Test-Path $DownloadFlutterWinDir)) {
    New-Item -ItemType Directory -Path $DownloadFlutterWinDir -Force | Out-Null
}

Copy-Item -Path $ZipPath -Destination "$DownloadFlutterWinDir\$ZipName" -Force

$DownloadUrl = "https://github.com/FSF77/openmoney-releases/raw/main/downloads/flutter/windows/$ZipName"

# 4. Atualização do version-flutter.json
$VersionJsonFile = "$StagingDir\version-flutter.json"
$JsonObj = @{}

if (Test-Path $VersionJsonFile) {
    try {
        $RawJson = Get-Content $VersionJsonFile -Raw -Encoding UTF8
        $JsonObj = $RawJson | ConvertFrom-Json
    } catch {
        $JsonObj = [PSCustomObject]@{}
    }
}

# Converte para hashtable para fácil manipulação
$Data = @{}
if ($JsonObj.PSObject.Properties.Name -contains "version") {
    foreach ($prop in $JsonObj.PSObject.Properties) {
        $Data[$prop.Name] = $prop.Value
    }
}

$Data["version"] = $Version
$Data["build"] = [int]$BuildNum
$Data["releaseDate"] = $ReleaseDate
$Data["title"] = "OpenMoney Flutter v$Version"
$Data["notes"] = $Notes
$Data["githubReleaseUrl"] = "https://github.com/FSF77/openmoney-releases"

$WinData = @{
    "version" = $Version
    "build" = [int]$BuildNum
    "releaseDate" = $ReleaseDate
    "downloadUrl" = $DownloadUrl
    "sha256" = $FileHash
    "sizeMb" = [int]$FileSizeMb
}
$Data["windows"] = $WinData

$UpdatedJson = $Data | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($VersionJsonFile, $UpdatedJson, [System.Text.Encoding]::UTF8)
Write-Host "version-flutter.json atualizado com sucesso." -ForegroundColor Green

# 5. Commit e Push no openmoney-releases
Set-Location $StagingDir
& git config user.name "FSF77"
& git config user.email "FSF77@users.noreply.github.com"
& git add version-flutter.json "downloads/flutter/windows/$ZipName"

$GitStatus = & git status --porcelain
if ([string]::IsNullOrWhiteSpace($GitStatus)) {
    Write-Host "ℹ️ Nenhuma alteração a commitar no repositório de releases."
} else {
    & git commit -m "Release OpenMoney Flutter Windows v$Version (Build $BuildNum) - $ReleaseDate"
    & git tag -f "v$Version-windows-flutter"
    Write-Host "📤 Enviando pacote para o GitHub (openmoney-releases)..." -ForegroundColor Yellow
    & git push origin main --tags --force
}

Set-Location $RootDir
Remove-Item -Recurse -Force $StagingDir

Write-Host ""
Write-Host "🎉 Versão Windows v$Version publicada com sucesso no openmoney-releases!" -ForegroundColor Green
Write-Host "🔗 Feed: https://raw.githubusercontent.com/FSF77/openmoney-releases/main/version-flutter.json"
Write-Host "📥 Download: $DownloadUrl"
