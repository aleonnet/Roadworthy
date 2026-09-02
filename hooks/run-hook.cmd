: << 'CMDBLOCK'
@echo off
REM Polyglot wrapper: cmd.exe runs the batch half on Windows and hands the
REM named hook to bash; every POSIX shell treats ':' as a no-op and runs the
REM shell half. Hook scripts are extensionless on purpose so Claude Code's
REM Windows ".sh" auto-detection never rewrites the command.
if "%~1"=="" (
    echo run-hook.cmd: missing hook name >&2
    exit /b 1
)
set "HOOK_DIR=%~dp0"
if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
REM No bash: fail open (exit 0) so the session keeps working without guardrails.
exit /b 0
CMDBLOCK
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_NAME="$1"
shift
exec bash "${HOOK_DIR}/${HOOK_NAME}" "$@"
