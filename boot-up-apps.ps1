# --- Developer Workspace Bootstrapper ---
# Run with: Right-click → "Run with PowerShell" OR double-click shortcut

# Keep window open on error
$host.UI.RawUI.WindowTitle = "Developer Workspace Bootstrapper"

# Set error preference to Continue (show errors but don't stop)
$ErrorActionPreference = "Continue"

# Clear host safely
try
{
    if ($Host.UI.RawUI.WindowSize.Width -gt 0)
    {
        Clear-Host
    }
} catch
{
}

$TotalStart = Get-Date

Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "   INITIALIZING DEVELOPMENT ENVIRONMENT        " -ForegroundColor Yellow -BackgroundColor DarkBlue
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "Started at: $($TotalStart.ToString('HH:mm:ss'))`n" -ForegroundColor White


# --- Required Tabs List ---
$RequiredTabs = @(
    "https://mail.google.com/mail/u/0/#inbox",
    "https://app.clickup.com/t/36243627/868hw5g9y",
    "https://discord.com/channels/297040613688475649/1019646242709569617/threads/1270372863412801587",
    "https://gemini.google.com/app/98e2e59142d7f626",
    "https://www.perplexity.ai/search/c19119d0-8c46-45ab-b677-aca1c172b54c",
    "https://chatgpt.com/",
    "https://chat.deepseek.com/a/chat/s/0998422e-b43f-4f8c-9628-7f6d9b9e6806",
    "https://chat.qwen.ai/",
    "https://laravel.com/docs/13.x/blade#anonymous-components",
    "https://dashboard.novu.co/env/dev_env_eGNsnTjbTT4sCU87/workflows",
    "http://localhost:8025/"
)


# --- Error Collection ---
$Errors = @()


function Ensure-ChromeTabs
{
    param ([array]$Urls)

    $debugPort = 9222

    try
    {
        $chromeDebug = netstat -ano 2>$null | Select-String ":$debugPort"
    } catch
    {
        $chromeDebug = $null
    }

    if (-not $chromeDebug)
    {
        Write-Host "[*] Starting Chrome with debugging port $debugPort..." -ForegroundColor Yellow
        Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        try
        {
            Start-Process "chrome.exe" "--remote-debugging-port=$debugPort --no-first-run --no-default-browser-check"
            Start-Sleep -Seconds 4
        } catch
        {
            Write-Host "[!] Failed to start Chrome with debug port: $($_.Exception.Message)" -ForegroundColor Red
            $Errors += "Chrome debug mode failed"
            return
        }
    }

    try
    {
        $tabs = Invoke-RestMethod "http://localhost:$debugPort/json" -TimeoutSec 10
        $openedCount = 0
        $closedCount = 0

        foreach ($url in $Urls)
        {
            try
            {
                $exists = $tabs | Where-Object { $_.url -eq $url -or $_.url.StartsWith($url.Split("?")[0]) }

                if ($exists)
                {
                    $shortUrl = $url.Substring(0, [Math]::Min(50, $url.Length))
                    Write-Host "[-] Already open: $shortUrl..." -ForegroundColor Gray
                } else
                {
                    $shortUrl = $url.Substring(0, [Math]::Min(50, $url.Length))
                    Write-Host "[+] Opening: $shortUrl..." -ForegroundColor Cyan
                    Start-Process "chrome.exe" $url -ErrorAction Stop
                    $openedCount++
                    Start-Sleep -Milliseconds 500
                }
            } catch
            {
                $shortUrl = $url.Substring(0, 40)
                $errorMsg = "[!] Error opening $shortUrl : $($_.Exception.Message)"
                $Errors += $errorMsg
                Write-Host $errorMsg -ForegroundColor Red
            }
        }

        Write-Host "`n[*] Checking for extra tabs to close..." -ForegroundColor Yellow
        foreach ($tab in $tabs)
        {
            $isRequired = $Urls | Where-Object { $tab.url -eq $_ -or $tab.url.StartsWith($_.Split("?")[0]) }

            if (-not $isRequired)
            {
                $title = if ($tab.title)
                { $tab.title.Substring(0, [Math]::Min(40, $tab.title.Length))
                } else
                { "Unknown"
                }
                Write-Host "[+] Closing: $title..." -ForegroundColor DarkGray
                try
                {
                    Invoke-RestMethod -Uri "http://localhost:$debugPort/json/close/$($tab.id)" -Method Get -TimeoutSec 5 -ErrorAction Stop
                    $closedCount++
                } catch
                {
                    # Ignore close errors silently
                }
            }
        }

        Write-Host "`n[✓] Tabs synchronized: $openedCount opened, $closedCount closed" -ForegroundColor Green

    } catch
    {
        $errorMsg = "[!] Could not check tabs: $($_.Exception.Message)"
        $Errors += $errorMsg
        Write-Host $errorMsg -ForegroundColor Yellow

        Write-Host "[*] Falling back to opening all tabs..." -ForegroundColor Yellow
        foreach ($url in $Urls)
        {
            try
            {
                $shortUrl = $url.Substring(0, 50)
                Write-Host "[+] Opening: $shortUrl..." -ForegroundColor Cyan
                Start-Process "chrome.exe" $url -ErrorAction Stop
                Start-Sleep -Milliseconds 500
            } catch
            {
                $shortUrl = $url.Substring(0, 40)
                $errorMsg = "[!] Failed to open $shortUrl"
                $Errors += $errorMsg
                Write-Host $errorMsg -ForegroundColor Red
            }
        }
    }
}


function Start-AppWithTimer
{
    param (
        [string]$ProcessName,
        [string]$FilePath,
        [string]$DisplayName,
        [string]$ArgumentList = ""
    )

    $AppTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try
    {
        $check = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    } catch
    {
        $check = $null
    }

    if ($check)
    {
        Write-Host "[-] $DisplayName already running." -ForegroundColor Gray
    } else
    {
        Write-Host "[+] Launching $DisplayName..." -ForegroundColor Cyan -NoNewline
        try
        {
            if ($ArgumentList -ne "")
            {
                Start-Process $FilePath -ArgumentList $ArgumentList -WindowStyle Minimized -ErrorAction Stop
            } else
            {
                Start-Process $FilePath -ErrorAction Stop
            }
            Start-Sleep -Seconds 1
            $AppTimer.Stop()
            Write-Host " Done! ($($AppTimer.Elapsed.Seconds)s)" -ForegroundColor Green
        } catch
        {
            $errorMsg = " Failed!`nError: $($_.Exception.Message)"
            $Errors += "$DisplayName : $errorMsg"
            Write-Host $errorMsg -ForegroundColor Red
        }
    }
}


# --- 1. Docker Engine ---
Write-Host "[>] Checking Docker Engine..." -ForegroundColor Cyan
if (Test-Path "C:\Program Files\Docker\Docker\Docker Desktop.exe")
{
    Start-AppWithTimer -ProcessName "Docker Desktop" `
        -FilePath "C:\Program Files\Docker\Docker\Docker Desktop.exe" `
        -DisplayName "Docker Desktop"
} else
{
    Write-Host "[!] Docker Desktop not found at expected path" -ForegroundColor Yellow
    $Errors += "Docker Desktop executable not found"
}

Start-Sleep -Seconds 3


# --- 2. Docker Containers ---
Write-Host "[>] Checking Docker Containers..." -ForegroundColor Cyan
try
{
    $originalPath = Get-Location
    Set-Location "C:\scripts\docker-sql-server" -ErrorAction Stop

    $dockerCheck = docker ps -q --filter "name=sql-server" 2>$null

    if (!$dockerCheck)
    {
        Write-Host "[+] Starting containers..." -ForegroundColor Cyan
        $composeOutput = docker-compose up -d 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            $Errors += "[!] Docker-compose failed: $composeOutput"
            Write-Host "[!] Docker-compose failed!" -ForegroundColor Red
            Write-Host $composeOutput -ForegroundColor Red
        } else
        {
            Write-Host "[✓] Containers started successfully" -ForegroundColor Green
        }
    } else
    {
        Write-Host "[-] Containers already active." -ForegroundColor Gray
    }

    Set-Location $originalPath -ErrorAction SilentlyContinue
} catch
{
    $errorMsg = "[!] Docker path issue: $($_.Exception.Message)"
    $Errors += $errorMsg
    Write-Host $errorMsg -ForegroundColor Red
}


# --- 3. Mailpit (SMTP + Web UI) ---
Write-Host "[+] Launching Mailpit (SMTP + http://localhost:8025)..." -ForegroundColor Cyan -NoNewline
$mailpitPath = "C:\scripts\mailpit-windows-amd64\mailpit.exe"
if (Test-Path $mailpitPath)
{
    try
    {
        Start-Process $mailpitPath -WindowStyle Minimized -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Host " Done!" -ForegroundColor Green
    } catch
    {
        $errorMsg = "[!] Failed to launch Mailpit: $($_.Exception.Message)"
        $Errors += $errorMsg
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
} else
{
    Write-Host " Not found!" -ForegroundColor Yellow
    $Errors += "Mailpit executable not found"
}


# --- 4. Chrome Browser ---
Start-AppWithTimer -ProcessName "chrome" `
    -FilePath "chrome.exe" `
    -DisplayName "Google Chrome"

Start-Sleep -Seconds 2


# --- 5. Open All Required Tabs ---
Ensure-ChromeTabs $RequiredTabs


# --- 6. Brave Browser ---
Start-AppWithTimer -ProcessName "brave" `
    -FilePath "brave.exe" `
    -DisplayName "Brave Browser"


# --- 7. WAMP Server ---
if (Test-Path "C:\wamp64\wampmanager.exe")
{
    Start-AppWithTimer -ProcessName "wampmanager" `
        -FilePath "C:\wamp64\wampmanager.exe" `
        -DisplayName "WAMP Server"
} else
{
    Write-Host "[!] WAMP Server not found" -ForegroundColor Yellow
    $Errors += "WAMP Server not found"
}


# --- 8. Bruno ---
Write-Host "[+] Launching Bruno..." -ForegroundColor Cyan -NoNewline
$brunoPath = "$env:LocalAppData\Programs\bruno\bruno.exe"
if (Test-Path $brunoPath)
{
    try
    {
        Start-Process $brunoPath -WindowStyle Minimized -ErrorAction Stop
        Start-Sleep 1
        Write-Host " Done!" -ForegroundColor Green
    } catch
    {
        $errorMsg = "[!] Failed to launch Bruno: $($_.Exception.Message)"
        $Errors += $errorMsg
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
} else
{
    Write-Host " Not found!" -ForegroundColor Yellow
    $Errors += "Bruno not found"
}


# --- 9. VS Code ---
Start-AppWithTimer -ProcessName "Code" `
    -FilePath "code" `
    -DisplayName "VS Code"


# --- 10. Google Teams (Web) ---
Write-Host "[+] Opening Google Teams (web)..." -ForegroundColor Cyan -NoNewline
try
{
    Start-Process "chrome.exe" "https://teams.google.com" -ErrorAction Stop
    Start-Sleep 1
    Write-Host " Done!" -ForegroundColor Green
} catch
{
    $errorMsg = "[!] Failed to open Google Teams: $($_.Exception.Message)"
    $Errors += $errorMsg
    Write-Host " Failed!" -ForegroundColor Red
    Write-Host $errorMsg -ForegroundColor Red
}


# --- 11. Microsoft Teams (Desktop) ---
Write-Host "[+] Launching Microsoft Teams (desktop)..." -ForegroundColor Cyan -NoNewline
$teamsNew = "$env:LocalAppData\Microsoft\WindowsApps\ms-teams.exe"
$teamsOld = "$env:LocalAppData\Microsoft\Teams\Update.exe"

try
{
    $teamsRunning = Get-Process -Name "ms-teams" -ErrorAction SilentlyContinue
} catch
{
    $teamsRunning = $null
}

if (-not $teamsRunning)
{
    try
    {
        if (Test-Path $teamsNew)
        {
            Start-Process $teamsNew -ErrorAction Stop
        } elseif (Test-Path $teamsOld)
        {
            Start-Process $teamsOld -ArgumentList "--processStart", "Teams.exe" -ErrorAction Stop
        } else
        {
            throw "Teams not found"
        }
        Start-Sleep 2
        Write-Host " Done!" -ForegroundColor Green
    } catch
    {
        $errorMsg = "[!] Failed to launch Teams: $($_.Exception.Message)"
        $Errors += $errorMsg
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host $errorMsg -ForegroundColor Red
    }
} else
{
    Write-Host " Already running." -ForegroundColor Gray
}


# --- 12. Stop Docker Desktop UI (Keep Containers Running) ---
Write-Host "`n[>] Closing Docker Desktop UI (containers stay running)..." -ForegroundColor Cyan
try
{
    Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-Host "[-] Docker Desktop UI closed. Containers active." -ForegroundColor Green
} catch
{
    # Silent
}


# --- Final Summary ---
$TotalEnd = Get-Date
$Duration = $TotalEnd - $TotalStart

Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "   ✓ BOOTSTRAP COMPLETE!                       " -ForegroundColor Green -BackgroundColor DarkGreen
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "Time Elapsed: $($Duration.Minutes)m $($Duration.Seconds)s" -ForegroundColor White


# --- Show Errors/Warnings ---
if ($Errors.Count -gt 0)
{
    Write-Host "`n===============================================" -ForegroundColor DarkRed
    Write-Host "   ! ERRORS / WARNINGS ($($Errors.Count))     " -ForegroundColor Red -BackgroundColor DarkRed
    Write-Host "===============================================" -ForegroundColor DarkRed
    foreach ($errorItem in $Errors)
    {
        Write-Host "  $errorItem" -ForegroundColor Red
    }
    Write-Host "===============================================" -ForegroundColor DarkRed
}


# --- Keep Window Open ---
Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "  Press any key to close this window..." -ForegroundColor Yellow -BackgroundColor DarkYellow
Write-Host "===============================================" -ForegroundColor Yellow

# Multiple methods to keep window open
try
{
    [Console]::ReadKey($true) | Out-Null
} catch
{
    Write-Host "Press Enter to continue..."
    Read-Host
}
