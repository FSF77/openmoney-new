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

# Obtem informacoes da release do macOS registradas no version.json
$VersionJsonFile = "$RootDir\version.json"
$MacReleaseNotes = ""
if (Test-Path $VersionJsonFile) {
    try {
        $RawJson = Get-Content $VersionJsonFile -Raw -Encoding UTF8
        $JsonObj = $RawJson | ConvertFrom-Json
        if ($JsonObj.notes) {
            $MacReleaseNotes = [string]$JsonObj.notes
        }
    } catch {}
}

# Sincroniza fallbackVersion e fallbackBuild em lib/services/update_service.dart
$UpdateServiceFile = "$RootDir\lib\services\update_service.dart"
if (Test-Path $UpdateServiceFile) {
    $UsContent = [System.IO.File]::ReadAllText($UpdateServiceFile, [System.Text.Encoding]::UTF8)
    $UsContent = $UsContent -replace "static const String fallbackVersion = '[^']*';", "static const String fallbackVersion = '$Version';"
    $UsContent = $UsContent -replace "static const int fallbackBuild = [0-9]+;", "static const int fallbackBuild = $BuildNum;"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($UpdateServiceFile, $UsContent, $Utf8NoBom)
}

$Notes = if ($CustomNotes) {
    $CustomNotes
} elseif ($MacReleaseNotes) {
    $MacReleaseNotes
} else {
    "OpenMoney Flutter v$Version para Windows - Versao oficial multiplataforma."
}
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

function Get-Sha256Checksum([string]$FilePath) {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        try {
            return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLower()
        } catch {}
    }
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($stream)
        $stream.Close()
        return ([System.BitConverter]::ToString($hashBytes) -replace '-','').ToLower()
    } catch {}
    try {
        $output = & certutil -hashfile $FilePath SHA256
        $lines = $output -split "`r?`n"
        if ($lines.Length -ge 2) {
            return ($lines[1] -replace '\s','').ToLower()
        }
    } catch {}
    return ""
}

$FileHash = Get-Sha256Checksum $ZipPath
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
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($VersionJsonFile, $UpdatedJson, $Utf8NoBom)
Write-Host "version.json atualizado com sucesso (UTF-8 sem BOM)." -ForegroundColor Green

# 3b. Atualizacao do README.md com os links de download da versao oficial
$ReadmeFile = "$RootDir\README.md"
if (Test-Path $ReadmeFile) {
    try {
        $ReadmeContent = [System.IO.File]::ReadAllText($ReadmeFile, [System.Text.Encoding]::UTF8)

        $MacVer = if ($Data.macos -and $Data.macos.version) { $Data.macos.version } else { $Version }
        $MacBuild = if ($Data.macos -and $Data.macos.build) { $Data.macos.build } else { "" }
        $MacUrl = if ($Data.macos -and $Data.macos.downloadUrl) { $Data.macos.downloadUrl } else { "" }
        $MacSize = if ($Data.macos -and $Data.macos.sizeMb) { $Data.macos.sizeMb } else { "" }
        $MacDate = if ($Data.macos -and $Data.macos.releaseDate) { $Data.macos.releaseDate } else { $ReleaseDate }
        $MacZip = if ($MacUrl) { Split-Path $MacUrl -Leaf } else { "OpenMoney-macOS-$MacVer.zip" }

        $WinVer = $Version
        $WinBuild = $BuildNum
        $WinUrl = $DownloadUrl
        $WinSize = $FileSizeMb
        $WinDate = $ReleaseDate
        $WinZip = $ZipName

        $WebVer = if ($Data.web -and $Data.web.version) { $Data.web.version } else { $Version }
        $WebDate = if ($Data.web -and $Data.web.releaseDate) { $Data.web.releaseDate } else { $ReleaseDate }

        $MacRow = if ($MacUrl) {
            "| 🍏 **macOS** | **v$MacVer** (Build $MacBuild) | [⬇️ Baixar $MacZip]($MacUrl) | ~$MacSize MB | $MacDate |"
        } else {
            "| 🍏 **macOS** | Em breve | Compilação em andamento | — | — |"
        }

        $WinRow = "| 🪟 **Windows** | **v$WinVer** (Build $WinBuild) | [⬇️ Baixar $WinZip]($WinUrl) | ~$WinSize MB | $WinDate |"
        $WebRow = "| 🌐 **Web** | **v$WebVer** | [🚀 Acessar App Web (openmoney.app.br)](https://openmoney.app.br) | — | $WebDate |"

        $StartMarker = "<!-- LATEST_DOWNLOADS_START -->"
        $EndMarker = "<!-- LATEST_DOWNLOADS_END -->"

        $HeaderTemplate = @"
$StartMarker
## 📥 Downloads da Versão Oficial

| Plataforma | Versão | Pacote / Instalador | Tamanho | Data |
| :--- | :--- | :--- | :--- | :--- |
$MacRow
$WinRow
$WebRow

"@

        $CommandsTemplate = @'
### ⚡ Instalação Rápida via Terminal / PowerShell

- **macOS** (Terminal):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.sh | bash
  ```

- **Windows** (PowerShell):
  ```powershell
  irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex
  ```

- **Windows** (Prompt / CMD):
  ```cmd
  curl -fsSL https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.bat -o install.bat && install.bat
  ```

---
<!-- LATEST_DOWNLOADS_END -->
'@

        $DownloadBlock = $HeaderTemplate + $CommandsTemplate

        $StartIdx = $ReadmeContent.IndexOf($StartMarker)
        $EndIdx = $ReadmeContent.IndexOf($EndMarker)
        if ($StartIdx -ge 0 -and $EndIdx -gt $StartIdx) {
            $Pre = $ReadmeContent.Substring(0, $StartIdx)
            $Post = $ReadmeContent.Substring($EndIdx + $EndMarker.Length)
            $ReadmeContent = $Pre + $DownloadBlock + $Post
        } else {
            $DashSep = "---`n"
            $SepIdx = $ReadmeContent.IndexOf($DashSep)
            if ($SepIdx -lt 0) {
                $DashSep = "---`r`n"
                $SepIdx = $ReadmeContent.IndexOf($DashSep)
            }
            if ($SepIdx -ge 0) {
                $Pre = $ReadmeContent.Substring(0, $SepIdx + $DashSep.Length)
                $Post = $ReadmeContent.Substring($SepIdx + $DashSep.Length)
                $ReadmeContent = $Pre + "`n" + $DownloadBlock + "`n`n" + $Post.TrimStart("`r`n".ToCharArray())
            } else {
                $ReadmeContent = $DownloadBlock + "`n`n" + $ReadmeContent
            }
        }

        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($ReadmeFile, $ReadmeContent, $Utf8NoBom)
        Write-Host "README.md atualizado com os links de download com sucesso." -ForegroundColor Green
    } catch {
        Write-Warning "Aviso: Nao foi possivel atualizar README.md: $_"
    }
}

# 4. Commit e Push no proprio repositorio openmoney-new
& git add README.md lib/services/update_service.dart pubspec.yaml pubspec.lock version.json install.sh install.ps1 install.bat "downloads/windows/$ZipName"

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
