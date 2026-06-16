# Check if running with proper permissions
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath)
    {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
        exit
    }
}

$host.UI.RawUI.WindowTitle = "Developer Workspace Bootstrapper"
$ErrorActionPreference = "Continue"

trap
{
    Write-Host "`n========================================" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "   CRITICAL ERROR DETECTED               " -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Category: $($_.Exception.GetType().Name)" -ForegroundColor Red
    Write-Host "`nThe window will stay open. Review error above." -ForegroundColor Yellow
    Write-Host "Press any key to exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    continue
}

try
{ Clear-Host
} catch
{
}

Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "   INITIALIZING DEVELOPMENT ENVIRONMENT        " -ForegroundColor Yellow -BackgroundColor DarkBlue
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "Started at: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
Write-Host ""

$Errors = @()
$TotalStart = Get-Date

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
    param([scriptblock]$Code, [string]$Name)
    try
    {
        & $Code
    } catch
    {
        $msg = "[!] $Name failed: $($_.Exception.Message)"
        $Errors += $msg
        Write-Host $msg -ForegroundColor Red
    }
}

function Start-AppSafe
{
    param([string]$Name, [string]$Path, [string]$Args = "")

    Write-Host "[>] Checking $Name..." -ForegroundColor Cyan

    try
    {
        $procName = (Split-Path $Path -Leaf).Replace(".exe","")
        $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
        if ($proc)
        {
            Write-Host "[-] $Name already running" -ForegroundColor Gray
            return
        }
    } catch
    {
    }

    if (Test-Path $Path)
    {
        Write-Host "[+] Launching $Name..." -ForegroundColor Cyan -NoNewline
        try
        {
            if ($Args)
            {
                Start-Process $Path -ArgumentList $Args -WindowStyle Minimized -ErrorAction Stop
            } else
            {
                Start-Process $Path -WindowStyle Minimized -ErrorAction Stop
            }
            Start-Sleep 1
            Write-Host " Done!" -ForegroundColor Green
        } catch
        {
            Write-Host " Failed!" -ForegroundColor Red
            $Errors += "$Name launch failed: $($_.Exception.Message)"
        }
    } else
    {
        Write-Host "[!] $Name not found at: $Path" -ForegroundColor Yellow
        $Errors += "$Name not found"
    }
}

Write-Host "`n[1/12] Docker Desktop" -ForegroundColor White
Safe-Execute {
    Start-AppSafe "Docker Desktop" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    Start-Sleep 3
} "Docker"

Write-Host "`n[2/12] Docker Containers" -ForegroundColor White
Safe-Execute {
    if (Test-Path "C:\scripts\docker-sql-server")
    {
        Push-Location "C:\scripts\docker-sql-server"
        try
        {
            $running = docker ps -q --filter "name=sql-server" 2>$null
            if (-not $running)
            {
                Write-Host "[+] Starting containers..." -ForegroundColor Cyan
                docker-compose up -d 2>&1 | Out-Null
                Write-Host "[✓] Containers started" -ForegroundColor Green
            } else
            {
                Write-Host "[-] Already running" -ForegroundColor Gray
            }
        } catch
        {
            Write-Host "[!] Docker error: $($_.Exception.Message)" -ForegroundColor Red
            $Errors += "Docker containers failed: $($_.Exception.Message)"
        }
        Pop-Location
    } else
    {
        Write-Host "[!] Docker folder not found" -ForegroundColor Yellow
        $Errors += "Docker folder not found"
    }
} "Containers"

Write-Host "`n[3/12] Mailpit" -ForegroundColor White
Safe-Execute {
    Start-AppSafe "Mailpit" "C:\scripts\mailpit-windows-amd64\mailpit.exe"
} "Mailpit"

Write-Host "`n[4/12] Chrome" -ForegroundColor White
Start-AppSafe "Chrome" "chrome.exe"

Start-Sleep 2

Write-Host "`n[5/12] Chrome Tabs" -ForegroundColor White
Safe-Execute {
    Write-Host "[+] Opening tabs..." -ForegroundColor Cyan
    foreach ($url in $RequiredTabs)
    {
        try
        {
            Start-Process "chrome.exe" $url -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 200
        } catch
        {
        }
    }
    Write-Host "[✓] Tabs opened" -ForegroundColor Green
} "Tabs"

Write-Host "`n[6/12] Brave" -ForegroundColor White
Start-AppSafe "Brave" "brave.exe"

Write-Host "`n[7/12] WAMP" -ForegroundColor White
Start-AppSafe "WAMP" "C:\wamp64\wampmanager.exe"

Write-Host "`n[8/12] Bruno" -ForegroundColor White
Start-AppSafe "Bruno" "$env:LocalAppData\Programs\bruno\bruno.exe"

Write-Host "`n[9/12] VS Code" -ForegroundColor White
Start-AppSafe "VS Code" "code"

Write-Host "`n[10/12] Google Teams" -ForegroundColor White
Safe-Execute {
    Write-Host "[+] Opening Google Teams..." -ForegroundColor Cyan
    Start-Process "chrome.exe" "https://teams.google.com" -ErrorAction SilentlyContinue
} "GTeams"

Write-Host "`n[11/12] MS Teams" -ForegroundColor White
Safe-Execute {
    $teams = "$env:LocalAppData\Microsoft\WindowsApps\ms-teams.exe"
    if (Test-Path $teams)
    {
        Start-AppSafe "MS Teams" $teams
    } else
    {
        Write-Host "[-] Teams not found" -ForegroundColor Yellow
        $Errors += "MS Teams not found"
    }
} "MSTeams"

Write-Host "`n[12/12] Close Docker UI" -ForegroundColor White
Safe-Execute {
    Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
    Write-Host "[-] Docker UI closed" -ForegroundColor Green
} "DockerUI"

$Duration = (Get-Date) - $TotalStart

Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "  ✓ BOOTSTRAP COMPLETE - WAITING 5 SECONDS     " -ForegroundColor Green -BackgroundColor DarkGreen
Write-Host "===============================================" -ForegroundColor Yellow
Write-Host "Time: $($Duration.Minutes)m $($Duration.Seconds)s" -ForegroundColor White

if ($Errors.Count -gt 0)
{
    Write-Host "`n[!] ERRORS ($($Errors.Count)):" -ForegroundColor Red
    $Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host "`nWaiting 5 seconds before closing..." -ForegroundColor Cyan
Start-Sleep 5

Write-Host "`n===============================================" -ForegroundColor Yellow
Write-Host "  PRESS ANY KEY TO CLOSE" -ForegroundColor Yellow -BackgroundColor DarkYellow
Write-Host "===============================================" -ForegroundColor Yellow

$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
