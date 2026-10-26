@echo off
rem ==============================================================================
rem OpenMoney Flutter - Atalho de Compilacao e Publicacao para Windows
rem ==============================================================================

chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish_release_windows.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo Falha na execucao do script de publicacao.
    pause
    exit /b %ERRORLEVEL%
)
