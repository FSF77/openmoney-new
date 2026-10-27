@echo off
rem ==============================================================================
rem OpenMoney Flutter - Atalho de Compilacao e Publicacao para Windows
rem ==============================================================================

chcp 65001 >nul
cls
echo ====================================================================
echo   OpenMoney Flutter - Compilacao e Publicacao para Windows
echo ====================================================================
echo.
echo ATENCAO: O fluxo padrao do projeto exige que a versao seja
echo editada, testada e publicada PRIMEIRO no macOS.
echo.
set /p "CONFIRMA=Voce ja realizou e publicou a versao primeiro no Mac? (S/N): "
if /i not "%CONFIRMA%"=="S" (
    echo.
    echo Operacao cancelada.
    echo Por favor, faca as alteracoes e a publicacao no macOS primeiro.
    echo.
    pause
    exit /b 0
)

echo.
echo Sincronizando com o repositorio remoto (git pull)...
git pull origin main
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERRO] Falha ao atualizar o repositorio com git pull.
    echo Verifique sua conexao ou conflitos locais antes de prosseguir.
    pause
    exit /b %ERRORLEVEL%
)

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish_release_windows.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo Falha na execucao do script de publicacao.
    pause
    exit /b %ERRORLEVEL%
)
