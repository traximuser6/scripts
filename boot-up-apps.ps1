# --- Developer Workspace Bootstrapper ---
# CRITICAL: Add this at the VERY TOP to prevent window from closing
$global:ErrorActionPreference = 'Continue'
trap
{
    Write-Host "`n[!!!] FATAL ERROR OCCURRED !!!" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "`nScript will stay open. Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    continue
}

# Force window to stay open
$host.UI.RawUI.WindowTitle = "Developer Workspace Bootstrapper - DO NOT CLOSE"

# Try to set execution policy for this session only
try
{
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
} catch
{
}

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

Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "   INITIALIZING DEVELOPMENT ENVIRONMENT        " -ForegroundColor Yellow -BackgroundColor DarkBlue
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "Started at: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
Write-Host ""

# --- Error Collection ---
$Errors = @()

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

function Safe-Execute
{
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName
    )

    try
    {
        & $ScriptBlock
        return $true
    } catch
    {
        $errorMsg = "[!] $OperationName failed: $($_.Exception.Message)"
        $Errors += $errorMsg
        Write-Host $errorMsg -ForegroundColor Red
        return $false
    }
}

function Ensure-ChromeTabs
{
    param ([array]$Urls)

    Write-Host "`n[>] Setting up Chrome tabs..." -ForegroundColor Cyan

    $debugPort = 9222
    $chromeStarted = $false

    # Check if debug port is already in use
    try
    {
        $chromeDebug = netstat -ano 2>$null | Select-String ":$debugPort"
        if ($chromeDebug)
        {
            Write-Host "[-] Chrome debug port already active" -ForegroundColor Gray
        } else
        {
            Write-Host "[*] Starting Chrome with debugging port $debugPort..." -ForegroundColor Yellow
            Stop-Process -Name chrome -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            $chromePath = @(
                "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
            )

            $found = $false
            foreach ($path in $chromePath)
            {
                if (Test-Path $path)
                {
                    Start-Process $path "--remote-debugging-port=$debugPort --no-first-run --no-default-browser-check"
                    $found = $true
                    break
                }
            }

            if (-not $found)
            {
                try
                {
                    Start-Process "chrome.exe" "--remote-debugging-port=$debugPort --no-first-run --no-default-browser-check"
                    $found = $true
                } catch
                {
                    Write-Host "[!] Could not find Chrome executable" -ForegroundColor Red
                    $Errors += "Chrome not found"
                }
            }

            if ($found)
            {
                Start-Sleep -Seconds 4
                $chromeStarted = $true
            }
        }
    } catch
    {
        Write-Host "[!] Error checking Chrome debug port: $($_.Exception.Message)" -ForegroundColor Red
        $Errors += "Chrome debug check failed"
    }

    # Try to manage tabs via API
    $apiWorked = $false
    try
    {
        $tabs = Invoke-RestMethod "http://localhost:$debugPort/json" -TimeoutSec 10 -ErrorAction Stop
        $openedCount = 0
        $closedCount = 0

        Write-Host "[*] Managing tabs via Chrome DevTools API..." -ForegroundColor Cyan

        foreach ($url in $Urls)
        {
            try
            {
                $exists = $tabs | Where-Object { $_.url -eq $url -or $_.url.StartsWith($url.Split("?")[0]) }

                if ($exists)
                {
                    Write-Host "[-] Already open: $($url.Substring(0, [Math]::Min(50, $url.Length)))" -ForegroundColor Gray
                } else
                {
                    Write-Host "[+] Opening: $($url.Substring(0, [Math]::Min(50, $url.Length)))" -ForegroundColor Cyan
                    Start-Process "chrome.exe" $url -ErrorAction SilentlyContinue
                    $openedCount++
                    Start-Sleep -Milliseconds 300
                }
            } catch
            {
                Write-Host "[!] Error opening tab: $($_.Exception.Message)" -ForegroundColor Red
                $Errors += "Failed to open: $url"
            }
        }

        # Close extra tabs
        Write-Host "[*] Checking for extra tabs to close..." -ForegroundColor Yellow
        foreach ($tab in $tabs)
        {
            if ($tab.url -and $tab.id)
            {
                $isRequired = $Urls | Where-Object { $tab.url -eq $_ -or $tab.url.StartsWith($_.Split("?")[0]) }

                if (-not $isRequired)
                {
                    $title = if ($tab.title)
                    { $tab.title.Substring(0, [Math]::Min(40, $tab.title.Length))
                    } else
                    { "Unknown"
                    }
                    Write-Host "[-] Closing: $title" -ForegroundColor DarkGray
                    try
                    {
                        Invoke-RestMethod -Uri "http://localhost:$debugPort/json/close/$($tab.id)" -Method Get -TimeoutSec 5 -ErrorAction SilentlyContinue
                        $closedCount++
                    } catch
                    {
                    }
                }
            }
        }

        Write-Host "[✓] Tabs synchronized: $openedCount opened, $closedCount closed" -ForegroundColor Green
        $apiWorked = $true

    } catch
    {
        Write-Host "[!] Chrome API not available, using fallback method..." -ForegroundColor Yellow
        $Errors += "Chrome API unavailable: $($_.Exception.Message)"
    }

    # Fallback: Just open all tabs
    if (-not $apiWorked)
    {
        Write-Host "[*] Opening all required tabs..." -ForegroundColor Cyan
        foreach ($url in $Urls)
        {
            try
            {
                Write-Host "[+] Opening: $($url.Substring(0, [Math]::Min(50, $url.Length)))" -ForegroundColor Cyan
                Start-Process "chrome.exe" $url -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 300
            } catch
            {
                Write-Host "[!] Failed to open: $url" -ForegroundColor Red
                $Errors += "Failed to open: $url"
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

    Write-Host "[>] Checking $DisplayName..." -ForegroundColor Cyan

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
        return
    }

    # Check if file exists
    if (-not (Test-Path $FilePath))
    {
        # Try to find it in PATH
        try
        {
            $cmd = Get-Command $FilePath -ErrorAction SilentlyContinue
            if ($cmd)
            {
                $FilePath = $cmd.Source
            } else
            {
                Write-Host "[!] $DisplayName not found at: $FilePath" -ForegroundColor Yellow
                $Errors += "$DisplayName not found"
                return
            }
        } catch
        {
            Write-Host "[!] $DisplayName not found at: $FilePath" -ForegroundColor Yellow
            $Errors += "$DisplayName not found"
            return
        }
    }

    Write-Host "[+] Launching $DisplayName..." -ForegroundColor Cyan -NoNewline
    try
    {
        if ($ArgumentList -ne "")
        {
            Start-Process $FilePath -ArgumentList $ArgumentList -WindowStyle Minimized -ErrorAction Stop
        } else
        {
            Start-Process $FilePath -WindowStyle Normal -ErrorAction Stop
        }
        Start-Sleep -Seconds 1
        Write-Host " Done!" -ForegroundColor Green
    } catch
    {
        Write-Host " Failed!" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $Errors += "$DisplayName launch failed: $($_.Exception.Message)"
    }
}

# ============================================
# MAIN EXECUTION
# ============================================

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 1: Docker Engine" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerPath)
    {
        Start-AppWithTimer -ProcessName "Docker Desktop" -FilePath $dockerPath -DisplayName "Docker Desktop"
        Start-Sleep -Seconds 3
    } else
    {
        Write-Host "[!] Docker Desktop not found" -ForegroundColor Yellow
        $Errors += "Docker Desktop not found"
    }
} "Docker Engine Check"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 2: Docker Containers" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    $originalPath = Get-Location
    $dockerDir = "C:\scripts\docker-sql-server"

    if (Test-Path $dockerDir)
    {
        Set-Location $dockerDir

        try
        {
            $dockerCheck = docker ps -q --filter "name=sql-server" 2>$null

            if (!$dockerCheck)
            {
                Write-Host "[+] Starting containers..." -ForegroundColor Cyan
                $composeOutput = docker-compose up -d 2>&1
                if ($LASTEXITCODE -ne 0)
                {
                    Write-Host "[!] Docker-compose failed!" -ForegroundColor Red
                    Write-Host $composeOutput -ForegroundColor Red
                    $Errors += "Docker-compose failed"
                } else
                {
                    Write-Host "[✓] Containers started" -ForegroundColor Green
                }
            } else
            {
                Write-Host "[-] Containers already active" -ForegroundColor Gray
            }
        } catch
        {
            Write-Host "[!] Docker command failed: $($_.Exception.Message)" -ForegroundColor Red
            $Errors += "Docker command failed"
        }

        Set-Location $originalPath
    } else
    {
        Write-Host "[!] Docker directory not found: $dockerDir" -ForegroundColor Yellow
        $Errors += "Docker directory not found"
    }
} "Docker Containers"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 3: Mailpit" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    $mailpitPath = "C:\scripts\mailpit-windows-amd64\mailpit.exe"
    if (Test-Path $mailpitPath)
    {
        Write-Host "[+] Launching Mailpit..." -ForegroundColor Cyan -NoNewline
        Start-Process $mailpitPath -WindowStyle Minimized -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Host " Done!" -ForegroundColor Green
    } else
    {
        Write-Host "[!] Mailpit not found" -ForegroundColor Yellow
        $Errors += "Mailpit not found"
    }
} "Mailpit Launch"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 4: Chrome Browser" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Start-AppWithTimer -ProcessName "chrome" -FilePath "chrome.exe" -DisplayName "Google Chrome"
Start-Sleep -Seconds 2

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 5: Chrome Tabs" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Ensure-ChromeTabs $RequiredTabs

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 6: Brave Browser" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Start-AppWithTimer -ProcessName "brave" -FilePath "brave.exe" -DisplayName "Brave Browser"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 7: WAMP Server" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    $wampPath = "C:\wamp64\wampmanager.exe"
    if (Test-Path $wampPath)
    {
        Start-AppWithTimer -ProcessName "wampmanager" -FilePath $wampPath -DisplayName "WAMP Server"
    } else
    {
        Write-Host "[!] WAMP Server not found" -ForegroundColor Yellow
        $Errors += "WAMP Server not found"
    }
} "WAMP Server"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 8: Bruno" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    $brunoPath = "$env:LocalAppData\Programs\bruno\bruno.exe"
    if (Test-Path $brunoPath)
    {
        Write-Host "[+] Launching Bruno..." -ForegroundColor Cyan -NoNewline
        Start-Process $brunoPath -WindowStyle Minimized -ErrorAction Stop
        Start-Sleep 1
        Write-Host " Done!" -ForegroundColor Green
    } else
    {
        Write-Host "[!] Bruno not found" -ForegroundColor Yellow
        $Errors += "Bruno not found"
    }
} "Bruno Launch"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 9: VS Code" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Start-AppWithTimer -ProcessName "Code" -FilePath "code" -DisplayName "VS Code"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 10: Google Teams (Web)" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    Write-Host "[+] Opening Google Teams..." -ForegroundColor Cyan -NoNewline
    Start-Process "chrome.exe" "https://teams.google.com" -ErrorAction Stop
    Start-Sleep 1
    Write-Host " Done!" -ForegroundColor Green
} "Google Teams"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 11: Microsoft Teams" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    $teamsRunning = Get-Process -Name "ms-teams" -ErrorAction SilentlyContinue

    if (-not $teamsRunning)
    {
        $teamsNew = "$env:LocalAppData\Microsoft\WindowsApps\ms-teams.exe"
        $teamsOld = "$env:LocalAppData\Microsoft\Teams\Update.exe"

        if (Test-Path $teamsNew)
        {
            Write-Host "[+] Launching Teams..." -ForegroundColor Cyan -NoNewline
            Start-Process $teamsNew -ErrorAction Stop
            Start-Sleep 2
            Write-Host " Done!" -ForegroundColor Green
        } elseif (Test-Path $teamsOld)
        {
            Write-Host "[+] Launching Teams (old version)..." -ForegroundColor Cyan -NoNewline
            Start-Process $teamsOld -ArgumentList "--processStart", "Teams.exe" -ErrorAction Stop
            Start-Sleep 2
            Write-Host " Done!" -ForegroundColor Green
        } else
        {
            Write-Host "[!] Microsoft Teams not found" -ForegroundColor Yellow
            $Errors += "Teams not found"
        }
    } else
    {
        Write-Host "[-] Teams already running" -ForegroundColor Gray
    }
} "Microsoft Teams"

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "  STEP 12: Close Docker UI" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Yellow

Safe-Execute {
    Write-Host "[>] Closing Docker Desktop UI..." -ForegroundColor Cyan
    Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-Host "[-] Docker UI closed (containers still running)" -ForegroundColor Green
} "Close Docker UI"

# ============================================
# FINAL SUMMARY
# ============================================

$TotalEnd = Get-Date
$Duration = $TotalEnd - $TotalStart

Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "   ✓ BOOTSTRAP COMPLETE!                       " -ForegroundColor Green -BackgroundColor DarkGreen
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "Time Elapsed: $($Duration.Minutes)m $($Duration.Seconds)s" -ForegroundColor White

if ($Errors.Count -gt 0)
{
    Write-Host "`n===============================================" -ForegroundColor DarkRed
    Write-Host "   ! ERRORS / WARNINGS ($($Errors.Count))     " -ForegroundColor Red -BackgroundColor DarkRed
    Write-Host "===============================================" -ForegroundColor DarkRed
    foreach ($errorItem in $Errors)
    {
        Write-Host "  • $errorItem" -ForegroundColor Red
    }
    Write-Host "===============================================" -ForegroundColor DarkRed
} else
{
    Write-Host "`n[✓] No errors detected!" -ForegroundColor Green
}

Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "  Press ANY KEY to close this window..." -ForegroundColor Yellow -BackgroundColor DarkYellow
Write-Host "===============================================" -ForegroundColor Yellow

# Multiple methods to keep window open - WILL NOT CLOSE UNTIL YOU PRESS A KEY
try
{
    Write-Host "`nWaiting for key press..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} catch
{
    Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray
    Read-Host
}

Write-Host "`nGoodbye!" -ForegroundColor Green
Start-Sleep -Milliseconds 500
