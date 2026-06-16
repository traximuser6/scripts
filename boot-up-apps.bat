@echo off
title Developer Workspace Bootstrapper
color 0E
echo ===============================================
echo    INITIALIZING DEVELOPMENT ENVIRONMENT
echo ===============================================
echo Started at: %time%
echo.

:: --- Helper Function Logic ---
:: We check if the process exists before starting it.

echo [1/12] Checking Docker Desktop...
tasklist /FI "IMAGENAME eq Docker Desktop.exe" 2>NUL | find /I /N "Docker Desktop.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] Docker Desktop is already running.
) else (
    echo [+] Launching Docker Desktop...
    if exist "C:\Program Files\Docker\Docker\Docker Desktop.exe" (
        start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    ) else (
        echo [!] Error: Docker Desktop executable not found.
    )
)
timeout /t 5 /nobreak >nul

echo [2/12] Checking Docker Containers...
cd /d C:\scripts\docker-sql-server
if exist docker-compose.yml (
    docker ps -q --filter "name=sql-server" >nul 2>&1
    if errorlevel 1 (
        echo [+] Starting containers...
        docker-compose up -d
    ) else (
        echo [-] SQL Server container is already active.
    )
) else (
    echo [!] Warning: Docker folder not found.
)
cd /d C:\projects\scripts

echo [3/12] Checking Mailpit...
tasklist /FI "IMAGENAME eq mailpit.exe" 2>NUL | find /I /N "mailpit.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] Mailpit is already running.
) else (
    echo [+] Launching Mailpit...
    if exist "C:\scripts\mailpit-windows-amd64\mailpit.exe" (
        start "" /min "C:\scripts\mailpit-windows-amd64\mailpit.exe"
    ) else (
        echo [!] Error: Mailpit executable not found.
    )
)

echo [4/12] Checking Chrome...
tasklist /FI "IMAGENAME eq chrome.exe" 2>NUL | find /I /N "chrome.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] Chrome is already running.
) else (
    echo [+] Launching Chrome...
    start chrome.exe
)
timeout /t 2 /nobreak >nul

echo [5/12] Opening Required Tabs...
:: We always open these because you might want fresh tabs,
:: but if Chrome wasn't running, it starts it now.
start chrome.exe "https://mail.google.com/mail/u/0/#inbox"
timeout /t 1 /nobreak >nul
start chrome.exe "https://app.clickup.com/t/36243627/868hw5g9y"
timeout /t 1 /nobreak >nul
start chrome.exe "https://discord.com/channels/297040613688475649/1019646242709569617/threads/1270372863412801587"
timeout /t 1 /nobreak >nul
start chrome.exe "https://gemini.google.com/app/98e2e59142d7f626"
timeout /t 1 /nobreak >nul
start chrome.exe "https://www.perplexity.ai/search/c19119d0-8c46-45ab-b677-aca1c172b54c"
timeout /t 1 /nobreak >nul
start chrome.exe "https://chatgpt.com/"
timeout /t 1 /nobreak >nul
start chrome.exe "https://chat.deepseek.com/a/chat/s/0998422e-b43f-4f8c-9628-7f6d9b9e6806"
timeout /t 1 /nobreak >nul
start chrome.exe "https://chat.qwen.ai/"
timeout /t 1 /nobreak >nul
start chrome.exe "https://laravel.com/docs/13.x/blade#anonymous-components"
timeout /t 1 /nobreak >nul
start chrome.exe "https://dashboard.novu.co/env/dev_env_eGNsnTjbTT4sCU87/workflows"
timeout /t 1 /nobreak >nul
start chrome.exe "http://localhost:8025/"

echo [6/12] Checking Brave...
tasklist /FI "IMAGENAME eq brave.exe" 2>NUL | find /I /N "brave.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] Brave is already running.
) else (
    echo [+] Launching Brave...
    start brave.exe
)

echo [7/12] Checking WAMP...
tasklist /FI "IMAGENAME eq wampmanager.exe" 2>NUL | find /I /N "wampmanager.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] WAMP Server is already running.
) else (
    echo [+] Launching WAMP...
    if exist "C:\wamp64\wampmanager.exe" (
        start "" /min "C:\wamp64\wampmanager.exe"
    ) else (
        echo [!] Error: WAMP not found.
    )
)

echo [8/12] Checking Bruno...
tasklist /FI "IMAGENAME eq bruno.exe" 2>NUL | find /I /N "bruno.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] Bruno is already running.
) else (
    echo [+] Launching Bruno...
    if exist "%LOCALAPPDATA%\Programs\bruno\bruno.exe" (
        start "" /min "%LOCALAPPDATA%\Programs\bruno\bruno.exe"
    ) else (
        echo [!] Error: Bruno not found.
    )
)

echo [9/12] Checking VS Code...
tasklist /FI "IMAGENAME eq Code.exe" 2>NUL | find /I /N "Code.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] VS Code is already running.
) else (
    echo [+] Launching VS Code...
    start code
)

echo [10/12] Opening Google Teams (Web)...
:: Always opens a new tab for web apps
start chrome.exe "https://teams.google.com"

echo [11/12] Checking MS Teams...
tasklist /FI "IMAGENAME eq ms-teams.exe" 2>NUL | find /I /N "ms-teams.exe">NUL
if "%ERRORLEVEL%"=="0" (
    echo [-] MS Teams is already running.
) else (
    echo [+] Launching MS Teams...
    if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\ms-teams.exe" (
        start "" "%LOCALAPPDATA%\Microsoft\WindowsApps\ms-teams.exe"
    ) else (
        echo [!] Error: MS Teams not found.
    )
)

echo [12/12] Closing Docker UI...
:: Only try to kill it if it's actually running to avoid error messages
tasklist /FI "IMAGENAME eq Docker Desktop.exe" 2>NUL | find /I /N "Docker Desktop.exe">NUL
if "%ERRORLEVEL%"=="0" (
    taskkill /F /IM "Docker Desktop.exe" >nul 2>&1
    echo [-] Docker Desktop UI closed.
) else (
    echo [-] Docker UI was not running.
)

echo.
echo ===============================================
echo   BOOTSTRAP COMPLETE
echo ===============================================
echo.
pause
