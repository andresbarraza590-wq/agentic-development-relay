@echo off
REM deva - front end for the Agentic AI Instruction Framework installer.
REM
REM   deva install [-Branch <b>] [-Source git^/share] [-Home <p>] [-NoPull]
REM   deva update [-Branch <b>]
REM   deva status ^/ version ^/ help
REM   deva <any other args>      passed through to install.bat
REM
REM Two deliberate structural choices:
REM 1. Thin shim. cmd.exe reads a running .bat by byte offset, so 'deva update'
REM    must never rewrite the file executing it. Logic lives in deva-cli.ps1,
REM    which PowerShell parses fully before running.
REM 2. Passthrough never goes through PowerShell. 'powershell.exe -File'
REM    mishandles GNU-style '--' tokens, so '--workspace ai' would be lost.
REM    Reserved verbs use single-dash flags and are safe via -File.
setlocal

set "SUB=%~1"
if "%SUB%"=="" set "SUB=help"

for %%V in (install update status version help) do if /i "%SUB%"=="%%V" goto :cli
goto :passthrough

:cli
set "DEVA_CLI=%~dp0scripts\deva-cli.ps1"
if not exist "%DEVA_CLI%" set "DEVA_CLI=%~dp0deva-cli.ps1"
if not exist "%DEVA_CLI%" (
    echo deva: cannot find deva-cli.ps1 near "%~dp0"
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DEVA_CLI%" %*
exit /b %ERRORLEVEL%

:passthrough
if not defined DEVA_HOME set "DEVA_HOME=<FRAMEWORK_HOME>"
if defined DEVA_INSTALLER goto :have_installer
if exist "%~dp0install.bat" (
    set "DEVA_INSTALLER=%~dp0install.bat"
) else (
    set "DEVA_INSTALLER=%DEVA_HOME%\deva\install.bat"
)
:have_installer
if not exist "%DEVA_INSTALLER%" (
    echo deva: installer not found: "%DEVA_INSTALLER%"
    echo Run 'deva install' first, or set DEVA_INSTALLER.
    exit /b 1
)
call "%DEVA_INSTALLER%" %*
exit /b %ERRORLEVEL%
