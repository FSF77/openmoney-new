@echo off
rem ==============================================================================
rem OpenMoney - Instalador Automatizado para Windows (.bat)
rem Executa o script oficial install.ps1 via PowerShell
rem ==============================================================================

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/FSF77/openmoney-new/main/install.ps1 | iex"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ❌ Falha na instalacao do OpenMoney.
    pause
    exit /b %ERRORLEVEL%
)
