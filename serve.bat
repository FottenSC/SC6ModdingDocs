@echo off
REM ===========================================================================
REM  serve.bat - Start the SC6 Modding Docs site locally with live reload.
REM
REM  First run : creates a .venv, installs dependencies, then serves.
REM  Later runs: activates venv and serves directly (fast).
REM
REM  Usage:
REM     serve.bat                 Serve on http://127.0.0.1:8000
REM     serve.bat 8080            Serve on the given port
REM     serve.bat --reinstall     Force reinstall of requirements.txt, then serve
REM     serve.bat --reinstall 8080
REM ===========================================================================

setlocal
cd /d "%~dp0"

REM ---- 0. Parse args --------------------------------------------------------
set "REINSTALL=0"
set "PORT="
:parse_args
if "%~1"=="" goto after_args
if /I "%~1"=="--reinstall" (
    set "REINSTALL=1"
    shift
    goto parse_args
)
set "PORT=%~1"
shift
goto parse_args
:after_args
if "%PORT%"=="" set "PORT=8000"

REM ---- 1. Find Python -------------------------------------------------------
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY (
    where python >nul 2>nul && set "PY=python"
)
if not defined PY (
    echo [serve] ERROR: Python 3 not found on PATH.
    echo [serve]        Install it from https://www.python.org/downloads/ and re-run.
    pause
    exit /b 1
)

REM ---- 2. Create venv if missing -------------------------------------------
if not exist ".venv\Scripts\activate.bat" (
    echo [serve] Creating virtual environment in .venv ...
    %PY% -m venv .venv
    if errorlevel 1 (
        echo [serve] ERROR: Failed to create venv.
        pause
        exit /b 1
    )
)

REM ---- 3. Activate venv -----------------------------------------------------
call ".venv\Scripts\activate.bat"
if errorlevel 1 (
    echo [serve] ERROR: Failed to activate venv.
    pause
    exit /b 1
)

REM ---- 4. Install deps if mkdocs isn't importable, or --reinstall was given
set "NEED_INSTALL=%REINSTALL%"
if "%NEED_INSTALL%"=="0" (
    python -c "import mkdocs, material" >nul 2>nul
    if errorlevel 1 set "NEED_INSTALL=1"
)

if "%NEED_INSTALL%"=="1" (
    echo [serve] Installing dependencies from requirements.txt ...
    python -m pip install --upgrade pip
    if errorlevel 1 (
        echo [serve] ERROR: pip upgrade failed.
        pause
        exit /b 1
    )
    python -m pip install -r requirements.txt
    if errorlevel 1 (
        echo [serve] ERROR: pip install failed.
        pause
        exit /b 1
    )
)

REM ---- 5. Serve -------------------------------------------------------------
echo.
echo [serve] Starting MkDocs on http://127.0.0.1:%PORT%
echo [serve] Press Ctrl+C to stop.
echo.

mkdocs serve -a 127.0.0.1:%PORT%

endlocal
