# ==============================================================================
# OpenMoney Flutter - Script de Compilacao e Publicacao para Windows (PowerShell)
# Repositorio Oficial: https://github.com/FSF77/openmoney-new
# ==============================================================================

param (
    [string]$CustomNotes = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

# 1. Extrai versao do pubspec.yaml
$PubspecContent = Get-Content "$RootDir\pubspec.yaml"
$VersionLine = $PubspecContent | Select-String -Pattern "^version:\s*([0-9\.]+)\+?([0-9]*)" | Select-Object -First 1

if ($VersionLine -match "version:\s*([0-9\.]+)\+?([0-9]*)") {
    $Version = $Matches[1]
    $BuildNum = if ($Matches[2]) { $Matches[2] } else { "1" }
} else {
    $Version = "2.0.0"
    $BuildNum = "1"
}

$Notes = if ($CustomNotes) { $CustomNotes } else { "OpenMoney Flutter v$Version para Windows - Versao oficial multiplataforma." }
$ReleaseDate = Get-Date -Format "dd/MM/yyyy"

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  OpenMoney Flutter Windows - Build and Publish v$Version+$BuildNum" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 2. Compilacao do Windows Release
Write-Host "Compilando aplicativo Windows em modo Release..." -ForegroundColor Yellow
& flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha na compilacao do Flutter Windows."
    exit 1
}

$ReleaseDir = "$RootDir\build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    $ReleaseDir = "$RootDir\build\windows\runner\Release"
}

if (-not (Test-Path "$ReleaseDir\openmoney.exe")) {
    Write-Error "Erro: Executavel nao encontrado em $ReleaseDir\openmoney.exe"
    exit 1
}

$DownloadsWinDir = "$RootDir\downloads\windows"
if (-not (Test-Path $DownloadsWinDir)) {
    New-Item -ItemType Directory -Path $DownloadsWinDir -Force | Out-Null
}

$ZipName = "OpenMoney-Windows-$Version.zip"
$ZipPath = "$DownloadsWinDir\$ZipName"
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Write-Host "Compactando $ZipName..." -ForegroundColor Yellow
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath -Force

$FileHash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLower()
$FileSizeMb = [math]::Round(((Get-Item $ZipPath).Length / 1MB))

Write-Host "Pacote gerado com sucesso: $ZipPath" -ForegroundColor Green
Write-Host "   Tamanho: ~$FileSizeMb MB"
Write-Host "   SHA256:  $FileHash"

$DownloadUrl = "https://github.com/FSF77/openmoney-new/raw/main/downloads/windows/$ZipName"

# 3. Atualizacao do version.json
$VersionJsonFile = "$RootDir\version.json"
$JsonObj = @{}

if (Test-Path $VersionJsonFile) {
    try {
        $RawJson = Get-Content $VersionJsonFile -Raw -Encoding UTF8
        $JsonObj = $RawJson | ConvertFrom-Json
    } catch {
        $JsonObj = [PSCustomObject]@{}
    }
}

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
$Data["githubReleaseUrl"] = "https://github.com/FSF77/openmoney-new"

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
Write-Host "version.json atualizado com sucesso." -ForegroundColor Green

# 4. Commit e Push no proprio repositorio openmoney-new
& git add pubspec.yaml pubspec.lock version.json install.sh install.ps1 install.bat "downloads/windows/$ZipName"

$GitStatus = & git status --porcelain
if ([string]::IsNullOrWhiteSpace($GitStatus)) {
    Write-Host "Nenhuma alteracao a commitar."
} else {
    & git commit -m "Release Windows v$Version (Build $BuildNum) - $ReleaseDate"
    & git tag -f "v$Version-windows"
    Write-Host "Enviando release para o GitHub..." -ForegroundColor Yellow
    & git push origin main "v$Version-windows" --force
}

Write-Host ""
Write-Host "Versao Windows v$Version publicada com sucesso no repositorio oficial!" -ForegroundColor Green
Write-Host "Feed: https://raw.githubusercontent.com/FSF77/openmoney-new/main/version.json"
Write-Host "Download: $DownloadUrl"
