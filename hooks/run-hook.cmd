: << 'CMDBLOCK'
@echo off
REM Polyglot wrapper: cmd.exe runs the batch half on Windows and hands the
REM named hook to bash; every POSIX shell treats ':' as a no-op and runs the
REM shell half. Hook scripts are extensionless on purpose so Claude Code's
REM Windows ".sh" auto-detection never rewrites the command.
REM
REM Claude Code runs a shell hook through Git Bash on Windows, or through
REM PowerShell when Git Bash is not installed -- and then this half finds no
REM bash. The WSL launcher in System32 is also called bash.exe and is NOT one:
REM it would run the hook inside a Linux distribution, if any, with Windows
REM paths. It is skipped on purpose.
if "%~1"=="" (
    echo run-hook.cmd: missing hook name >&2
    exit /b 1
)
set "HOOK_DIR=%~dp0"
set "RW_BASH="
if exist "C:\Program Files\Git\bin\bash.exe" set "RW_BASH=C:\Program Files\Git\bin\bash.exe"
if not defined RW_BASH for /f "delims=" %%B in ('where bash 2^>nul') do (
    if not defined RW_BASH echo %%B | findstr /I /V "\\System32\\" >nul && set "RW_BASH=%%B"
)
if not defined RW_BASH goto nobash
"%RW_BASH%" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%

:nobash
REM No bash: the hook cannot run, and a guardrail that cannot run does not pass
REM the call unguarded. Until 0.6.1 this branch exited 0 in silence while the
REM CHANGELOG said it warned and refused (measured 2026-09-14). The policy is
REM each hook's own crash policy: a guard fails closed (exit 2 blocks the tool
REM call, the reason goes to stderr); principles and stop-gate warn with exit 1,
REM because exit 2 there would erase the prompt or trap the session in a wall
REM it cannot argue with. The CI executes this branch on a Windows runner.
echo Roadworthy/%~1: no bash found on this machine, so the guardrail cannot run. Install Git for Windows (its bash) or disable the plugin in /plugin; this call is refused rather than passed unguarded. >&2
if /I "%~1"=="principles" exit /b 1
if /I "%~1"=="stop-gate" exit /b 1
exit /b 2
CMDBLOCK
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_NAME="$1"
shift
exec bash "${HOOK_DIR}/${HOOK_NAME}" "$@"
