#requires -Version 5.1
<#
PHP Version Manager for Windows
Commands:
  php72, php80, php81, php82, php83, php84, php85
  cmp72, cmp80, cmp81, cmp82, cmp83, cmp84, cmp85
  php = active PHP
  cmp = Composer using active PHP

Run:
  .\generate-php-bat-files.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIG
# ============================================================

$ManagerRoot = Join-Path $env:USERPROFILE ".php-manager"
$RegistryFile = Join-Path $ManagerRoot "registry.json"
$ActiveFile = Join-Path $ManagerRoot "active.json"
$DownloadDir = Join-Path $ManagerRoot "downloads"
$VersionRoot = Join-Path $ManagerRoot "versions"
$WrapperRoot = Join-Path $ManagerRoot "bin"

$ReleaseUrl = "https://windows.php.net/downloads/releases/"
$ArchiveUrl = "https://windows.php.net/downloads/releases/archives/"

# ============================================================
# UI
# ============================================================

function Write-Title([string]$Text) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-OK([string]$Text) { Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text) { Write-Host "[ERROR] $Text" -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host "[INFO] $Text" -ForegroundColor Gray }

# ============================================================
# INITIALIZE
# ============================================================

function Initialize-Manager {
    foreach ($dir in @($ManagerRoot, $DownloadDir, $VersionRoot, $WrapperRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    }

    if (-not (Test-Path -LiteralPath $RegistryFile)) {
        @{ installations = @() } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
    }

    if (-not (Test-Path -LiteralPath $ActiveFile)) {
        @{ activePath = $null; activeVersion = $null } | ConvertTo-Json | Set-Content -LiteralPath $ActiveFile -Encoding UTF8
    }
}

# ============================================================
# REGISTRY
# ============================================================

function Get-Registry {
    if (-not (Test-Path -LiteralPath $RegistryFile)) { Initialize-Manager }

    try {
        $raw = Get-Content -LiteralPath $RegistryFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{ installations = @() } }
        $data = $raw | ConvertFrom-Json
        if ($null -eq $data.installations) { $data | Add-Member NoteProperty installations @() }
        return $data
    } catch {
        Write-Warn "Invalid registry. Recreating."
        @{ installations = @() } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
        return [PSCustomObject]@{ installations = @() }
    }
}

function Save-Registry($Registry) {
    $Registry | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
}

# ============================================================
# ACTIVE PHP
# ============================================================

function Get-Active {
    if (-not (Test-Path -LiteralPath $ActiveFile)) { return [PSCustomObject]@{ activePath = $null; activeVersion = $null } }

    try {
        $raw = Get-Content -LiteralPath $ActiveFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{ activePath = $null; activeVersion = $null } }
        return $raw | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ activePath = $null; activeVersion = $null }
    }
}

function Set-Active([string]$PhpPath, [string]$Version) {
    @{ activePath = $PhpPath; activeVersion = $Version; updatedAt = (Get-Date).ToString("o") } |
        ConvertTo-Json | Set-Content -LiteralPath $ActiveFile -Encoding UTF8
    Write-OK "Active PHP: $Version"
}

# ============================================================
# VERSION HELPERS
# ============================================================

function Get-ShortVersion([string]$Version) {
    if ($Version -match "^(\d+)\.(\d+)") { return "$($Matches[1])$($Matches[2])" }
    return $null
}

function Test-VersionMatch([string]$Actual, [string]$Requested) {
    try {
        $v = [version]$Actual
        if ($Requested -match "^\d+\.\d+$") {
            $p = $Requested.Split(".")
            return $v.Major -eq [int]$p[0] -and $v.Minor -eq [int]$p[1]
        }
        if ($Requested -match "^\d+\.\d+\.\d+$") { return $v -eq [version]$Requested }
    } catch {}
    return $false
}

function Get-PhpVersion([string]$PhpExe) {
    if (-not (Test-Path -LiteralPath $PhpExe)) { return $null }
    try {
        $v = & $PhpExe -r "echo PHP_VERSION;" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return ([string]$v).Trim() }
    } catch {}
    return $null
}

# ============================================================
# PHP DISCOVERY
# ============================================================

function Add-PhpResult($List, [string]$Path, [string]$Source) {
    if (-not (Test-Path -LiteralPath $Path)) { return }

    $full = [IO.Path]::GetFullPath($Path)
    if ($List | Where-Object { $_.Path -ieq $full }) { return }

    $version = Get-PhpVersion $full
    if (-not $version) { return }

    $List.Add([PSCustomObject]@{
        Version = $version
        Path = $full
        Source = $Source
    })
}

function Find-PhpExecutables {
    $results = New-Object System.Collections.Generic.List[object]

    $registry = Get-Registry
    foreach ($item in @($registry.installations)) {
        if ($null -ne $item -and $item.path) { Add-PhpResult $results ([string]$item.path) "Registry" }
    }

    $roots = @(
        "C:\PHP",
        "C:\php",
        "C:\wamp64\bin\php",
        "C:\wamp\bin\php",
        "C:\xampp\php",
        "C:\tools\php",
        $VersionRoot
    )

    foreach ($scope in @("User", "Machine")) {
        try {
            $p = [Environment]::GetEnvironmentVariable("Path", $scope)
            if ($p) { $roots += $p -split ";" }
        } catch {}
    }

    $roots = @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)

    foreach ($root in $roots) {
        try {
            Get-ChildItem -LiteralPath $root -Filter "php.exe" -File -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object { Add-PhpResult $results $_.FullName "Scan" }
        } catch {}
    }

    return @($results | Sort-Object @{ Expression = { try { [version]$_.Version } catch { [version]"0.0.0" } }; Descending = $true })
}

# ============================================================
# REGISTER
# ============================================================

function Register-Php([string]$PhpPath, [string]$Version, [string]$Architecture = "unknown", [string]$ThreadSafety = "unknown", [string]$InstallPath) {
    $registry = Get-Registry
    $registry.installations = @($registry.installations | Where-Object { $_.path -ine $PhpPath })
    $registry.installations += [PSCustomObject]@{
        version = $Version
        path = $PhpPath
        installPath = $InstallPath
        architecture = $Architecture
        threadSafety = $ThreadSafety
        registeredAt = (Get-Date).ToString("o")
    }
    Save-Registry $registry
}

# ============================================================
# BATCH ESCAPING
# ============================================================

function Escape-BatchPath([string]$Path) {
    return $Path.Replace("%", "%%")
}

# ============================================================
# PHP WRAPPER
# ============================================================

function New-PhpWrapper([string]$PhpPath, [string]$Version) {
    $short = Get-ShortVersion $Version
    if (-not $short) { return }

    $wrapper = Join-Path $WrapperRoot "php$short.bat"
    $safePath = Escape-BatchPath $PhpPath

    $content = @"
@echo off
setlocal
set "PHP_EXE=$safePath"
if not exist "%PHP_EXE%" (
 echo ERROR: PHP $Version not found.
 echo %PHP_EXE%
 exit /b 1
)
"%PHP_EXE%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@

    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created php$short.bat -> $PhpPath"
}

# ============================================================
# COMPOSER DISCOVERY
# ============================================================

function Find-Composer {
    $candidates = @(
        "C:\ProgramData\ComposerSetup\bin\composer.phar",
        (Join-Path $env:APPDATA "Composer\composer.phar"),
        (Join-Path $env:LOCALAPPDATA "Composer\composer.phar")
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return [PSCustomObject]@{ Type = "phar"; Path = $path } }
    }

    $cmd = Get-Command composer -ErrorAction SilentlyContinue
    if ($cmd) {
        $source = $cmd.Source
        if ($source -and $source -match "\.bat$" -and (Test-Path -LiteralPath $source)) {
            try {
                $bat = Get-Content -LiteralPath $source -Raw
                $m = [regex]::Match($bat, '"([^"]*composer\.phar)"', "IgnoreCase")
                if ($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value)) {
                    return [PSCustomObject]@{ Type = "phar"; Path = $m.Groups[1].Value }
                }
            } catch {}
        }
        return [PSCustomObject]@{ Type = "command"; Path = $source }
    }

    return $null
}

# ============================================================
# COMPOSER WRAPPER
# ============================================================

function New-ComposerWrapper([string]$PhpPath, [string]$Version) {
    $composer = Find-Composer
    $short = Get-ShortVersion $Version
    if (-not $short) { return }

    $wrapper = Join-Path $WrapperRoot "cmp$short.bat"

    if (-not $composer) {
        Write-Warn "Composer not found. cmp$short.bat skipped."
        return
    }

    if ($composer.Type -eq "phar") {
        $safePhp = Escape-BatchPath $PhpPath
        $safePhar = Escape-BatchPath $composer.Path

        $content = @"
@echo off
setlocal
set "PHP_EXE=$safePhp"
set "COMPOSER_PHAR=$safePhar"
if not exist "%PHP_EXE%" (
 echo ERROR: PHP $Version not found.
 echo %PHP_EXE%
 exit /b 1
)
if not exist "%COMPOSER_PHAR%" (
 echo ERROR: Composer PHAR not found.
 echo %COMPOSER_PHAR%
 exit /b 1
)
"%PHP_EXE%" "%COMPOSER_PHAR%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@
    } else {
        Write-Warn "Composer was found as command rather than PHAR. cmp$short will use composer.bat."
        $safePhp = Escape-BatchPath $PhpPath
        $safeCmd = Escape-BatchPath $composer.Path

        $content = @"
@echo off
setlocal
set "PHP_EXE=$safePhp"
set "COMPOSER_CMD=$safeCmd"
if not exist "%PHP_EXE%" (
 echo ERROR: PHP $Version not found.
 exit /b 1
)
call "%COMPOSER_CMD%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@
    }

    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created cmp$short.bat -> PHP $Version"
}

# ============================================================
# ACTIVE WRAPPERS
# ============================================================

function New-ActivePhpWrapper {
    $wrapper = Join-Path $WrapperRoot "php.bat"
    $content = @"
@echo off
setlocal
set "ACTIVE_FILE=$ActiveFile"
if not exist "%ACTIVE_FILE%" (
 echo ERROR: Active PHP configuration not found.
 exit /b 1
)
for /f "usebackq delims=" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-active-php.ps1"`) do set "PHP_EXE=%%A"
if not defined PHP_EXE (
 echo ERROR: No active PHP selected.
 exit /b 1
)
if not exist "%PHP_EXE%" (
 echo ERROR: Active PHP executable not found.
 echo %PHP_EXE%
 exit /b 1
)
"%PHP_EXE%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@
    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created active php command"
}

function New-ActiveComposerWrapper {
    $composer = Find-Composer
    if (-not $composer) {
        Write-Warn "Composer not found. cmp.bat skipped."
        return
    }

    $wrapper = Join-Path $WrapperRoot "cmp.bat"

    if ($composer.Type -eq "phar") {
        $safePhar = Escape-BatchPath $composer.Path

        $content = @"
@echo off
setlocal
for /f "usebackq delims=" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-active-php.ps1"`) do set "PHP_EXE=%%A"
if not defined PHP_EXE (
 echo ERROR: No active PHP selected.
 exit /b 1
)
if not exist "%PHP_EXE%" (
 echo ERROR: Active PHP not found.
 echo %PHP_EXE%
 exit /b 1
)
set "COMPOSER_PHAR=$safePhar"
if not exist "%COMPOSER_PHAR%" (
 echo ERROR: Composer PHAR not found.
 exit /b 1
)
"%PHP_EXE%" "%COMPOSER_PHAR%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@
    } else {
        $safeCmd = Escape-BatchPath $composer.Path

        $content = @"
@echo off
setlocal
for /f "usebackq delims=" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-active-php.ps1"`) do set "PHP_EXE=%%A"
if not defined PHP_EXE (
 echo ERROR: No active PHP selected.
 exit /b 1
)
set "COMPOSER_CMD=$safeCmd"
call "%COMPOSER_CMD%" %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
"@
    }

    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created active cmp command"
}

# ============================================================
# ACTIVE PHP HELPER
# ============================================================

function New-ActivePhpHelper {
    $helper = Join-Path $WrapperRoot "get-active-php.ps1"

    $content = @"
`$ErrorActionPreference = "SilentlyContinue"
`$file = '$($ActiveFile.Replace("'","''"))'
if (Test-Path -LiteralPath `$file) {
    try {
        `$j = Get-Content -LiteralPath `$file -Raw | ConvertFrom-Json
        if (`$j.activePath) { Write-Output `$j.activePath }
    } catch {}
}
"@

    Set-Content -LiteralPath $helper -Value $content -Encoding UTF8
}

# ============================================================
# PATH
# ============================================================

function Add-ManagerToUserPath {
    $target = $WrapperRoot.TrimEnd('\')
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @()

    if ($userPath) {
        $entries = @($userPath -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $exists = $entries | Where-Object { $_.TrimEnd('\') -ieq $target }

    if (-not $exists) {
        $entries += $target
        [Environment]::SetEnvironmentVariable("Path", ($entries -join ";"), "User")
        Write-OK "Added $target to User PATH."
    } else {
        Write-OK "Wrapper directory already exists in User PATH."
    }

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $env:Path = (($entries -join ";") + ";" + $machinePath).Trim(";")
    Write-OK "Current PowerShell PATH updated."
}

# ============================================================
# CONFLICT DETECTION
# ============================================================

function Find-CommandConflicts([string]$CommandName) {
    $found = @()

    foreach ($dir in ($env:Path -split ";" | Where-Object { $_ })) {
        $file = Join-Path $dir "$CommandName.bat"
        if (Test-Path -LiteralPath $file) { $found += $file }
        $file = Join-Path $dir "$CommandName.cmd"
        if (Test-Path -LiteralPath $file) { $found += $file }
        $file = Join-Path $dir "$CommandName.exe"
        if (Test-Path -LiteralPath $file) { $found += $file }
    }

    return @($found | Sort-Object -Unique)
}

function Verify-Wrapper([string]$CommandName, [string]$ExpectedPhpPath, [string]$ExpectedVersion) {
    $wrapper = Join-Path $WrapperRoot "$CommandName.bat"

    if (-not (Test-Path -LiteralPath $wrapper)) {
        Write-Err "$CommandName wrapper missing."
        return $false
    }

    $conflicts = @(Find-CommandConflicts $CommandName)

    if ($conflicts.Count -gt 1) {
        Write-Warn "Multiple $CommandName commands found:"
        $conflicts | ForEach-Object { Write-Host "  $_" }
    }

    $resolved = Get-Command $CommandName -ErrorAction SilentlyContinue

    if (-not $resolved) {
        Write-Err "$CommandName is not available in current PATH."
        return $false
    }

    if ($resolved.Source -ine $wrapper) {
        Write-Warn "$CommandName resolves to:"
        Write-Host "  $($resolved.Source)"
        Write-Warn "Expected:"
        Write-Host "  $wrapper"
        return $false
    }

    if ($ExpectedPhpPath) {
        $content = Get-Content -LiteralPath $wrapper -Raw
        if ($content -notmatch [regex]::Escape($ExpectedPhpPath)) {
            Write-Err "$CommandName mapping is incorrect."
            return $false
        }
    }

    Write-OK "$CommandName -> PHP $ExpectedVersion"
    return $true
}

# ============================================================
# REBUILD
# ============================================================

function Rebuild-Wrappers {
    Write-Title "Rebuilding PHP / Composer Wrappers"

    $versions = @(Find-PhpExecutables)

    if ($versions.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }

    New-ActivePhpHelper

    foreach ($php in $versions) {
        $actual = Get-PhpVersion $php.Path
        if (-not $actual) { continue }

        Register-Php -PhpPath $php.Path -Version $actual -InstallPath (Split-Path $php.Path -Parent)
        New-PhpWrapper -PhpPath $php.Path -Version $actual
        New-ComposerWrapper -PhpPath $php.Path -Version $actual
    }

    New-ActivePhpWrapper
    New-ActiveComposerWrapper
    Add-ManagerToUserPath

    Write-OK "All wrappers rebuilt."
}

# ============================================================
# LIST
# ============================================================

function Show-InstalledVersions {
    Write-Title "Installed PHP Versions"

    $versions = @(Find-PhpExecutables)
    $active = Get-Active

    if ($versions.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }

    foreach ($php in $versions) {
        $marker = if ($active.activePath -and $php.Path -ieq $active.activePath) { "[ACTIVE]" } else { "        " }
        $short = Get-ShortVersion $php.Version
        Write-Host "$marker PHP $($php.Version)" -ForegroundColor Cyan
        Write-Host "         $($php.Path)" -ForegroundColor Gray
        Write-Host "         php$short / cmp$short" -ForegroundColor Yellow
    }
}

# ============================================================
# SWITCH
# ============================================================

function Switch-ActivePhp {
    Write-Title "Switch Active PHP"

    $versions = @(Find-PhpExecutables)
    if ($versions.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }

    for ($i = 0; $i -lt $versions.Count; $i++) {
        Write-Host "[$($i + 1)] PHP $($versions[$i].Version)" -ForegroundColor Cyan
        Write-Host "    $($versions[$i].Path)" -ForegroundColor Gray
    }

    $choice = Read-Host "Select PHP number"
    if ($choice -notmatch "^\d+$") { Write-Err "Invalid selection."; return }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $versions.Count) { Write-Err "Invalid selection."; return }

    $selected = $versions[$index]
    Set-Active -PhpPath $selected.Path -Version $selected.Version
    New-ActivePhpHelper
    New-ActivePhpWrapper
    New-ActiveComposerWrapper

    Write-OK "php -> PHP $($selected.Version)"
    Write-OK "cmp -> PHP $($selected.Version)"
}

# ============================================================
# ACTIVE INFO
# ============================================================

function Show-ActivePhp {
    Write-Title "Active PHP"

    $active = Get-Active

    if (-not $active.activePath) {
        Write-Warn "No active PHP selected."
        return
    }

    Write-Host "Version : $($active.activeVersion)" -ForegroundColor Cyan
    Write-Host "Path    : $($active.activePath)" -ForegroundColor Gray

    if (Test-Path -LiteralPath $active.activePath) {
        $actual = Get-PhpVersion $active.activePath
        if ($actual) {
            Write-OK "Executable reports PHP $actual"
        } else {
            Write-Err "PHP executable could not be executed."
        }
    } else {
        Write-Err "Active PHP executable does not exist."
    }
}

# ============================================================
# VERIFY
# ============================================================

function Verify-Commands {
    Write-Title "Verify Commands"

    $versions = @(Find-PhpExecutables)

    foreach ($php in $versions) {
        $short = Get-ShortVersion $php.Version
        Verify-Wrapper "php$short" $php.Path $php.Version | Out-Null
        Verify-Wrapper "cmp$short" $php.Path $php.Version | Out-Null
    }

    $active = Get-Active

    if ($active.activePath) {
        Verify-Wrapper "php" $active.activePath $active.activeVersion | Out-Null
        Write-OK "Active mapping: php -> $($active.activeVersion)"
        Write-OK "Active mapping: cmp -> $($active.activeVersion)"
    }
}

# ============================================================
# REMOVE
# ============================================================

function Remove-Php {
    Write-Title "Remove PHP"

    $versions = @(Find-PhpExecutables)
    if ($versions.Count -eq 0) { Write-Warn "No PHP installations found."; return }

    for ($i = 0; $i -lt $versions.Count; $i++) {
        Write-Host "[$($i + 1)] PHP $($versions[$i].Version)" -ForegroundColor Cyan
        Write-Host "    $($versions[$i].Path)" -ForegroundColor Gray
    }

    $choice = Read-Host "Select version"
    if ($choice -notmatch "^\d+$") { return }

    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $versions.Count) { Write-Err "Invalid selection."; return }

    $selected = $versions[$index]
    $active = Get-Active

    if ($active.activePath -and $active.activePath -ieq $selected.Path) {
        Write-Warn "This PHP is active. Switch active PHP first."
        return
    }

    Write-Host "PHP $($selected.Version)"
    Write-Host $selected.Path

    $confirm = Read-Host "Really remove this PHP? [y/N]"
    if ($confirm -notmatch "^[Yy]$") { return }

    $installPath = Split-Path $selected.Path -Parent
    Remove-Item -LiteralPath $installPath -Recurse -Force

    $registry = Get-Registry
    $registry.installations = @($registry.installations | Where-Object { $_.path -ine $selected.Path })
    Save-Registry $registry

    $short = Get-ShortVersion $selected.Version
    foreach ($name in @("php$short.bat", "cmp$short.bat")) {
        $file = Join-Path $WrapperRoot $name
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    }

    Write-OK "PHP $($selected.Version) removed."
}

# ============================================================
# WEB RELEASES
# ============================================================

function Get-WebText([string]$Url) {
    Write-Info "Fetching $Url"
    $ProgressPreference = "SilentlyContinue"
    try {
        return (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60).Content
    } finally {
        $ProgressPreference = "Continue"
    }
}

function Get-ReleaseFiles([string]$Html) {
    $pattern = 'php-\d+\.\d+\.\d+-(?:nts-)?Win32-[^"\s<>]+-(?:x64|x86)\.zip'
    return @(
        [regex]::Matches($Html, $pattern, "IgnoreCase") |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
    )
}

function Parse-PhpZip([string]$FileName) {
    if ($FileName -match '^php-(\d+\.\d+\.\d+)-(nts-)?Win32-.*-(x64|x86)\.zip$') {
        return [PSCustomObject]@{
            FileName = $FileName
            Version = $Matches[1]
            ThreadSafety = if ($Matches[2]) { "nts" } else { "ts" }
            Architecture = $Matches[3]
        }
    }
    return $null
}

function Find-PhpRelease([string]$RequestedVersion, [string]$ThreadSafety, [string]$Architecture) {
    $current = $null
    $archive = $null

    try { $current = Get-WebText $ReleaseUrl } catch { Write-Warn "Current releases unavailable." }
    try { $archive = Get-WebText $ArchiveUrl } catch { Write-Warn "Archive releases unavailable." }

    $files = @()
    if ($current) { $files += Get-ReleaseFiles $current }
    if ($archive) { $files += Get-ReleaseFiles $archive }
    $files = @($files | Sort-Object -Unique)

    $parsed = @(
        $files | ForEach-Object {
            $x = Parse-PhpZip $_
            if ($x -and $x.Architecture -eq $Architecture -and $x.ThreadSafety -eq $ThreadSafety) { $x }
        }
    )

    if ($RequestedVersion -match "^\d+\.\d+$") {
        $parsed = @($parsed | Where-Object { $_.Version -like "$RequestedVersion.*" })
    } else {
        $parsed = @($parsed | Where-Object { $_.Version -eq $RequestedVersion })
    }

    if ($parsed.Count -eq 0) {
        throw "No official Windows PHP build found for PHP $RequestedVersion / $Architecture / $ThreadSafety."
    }

    $selected = $parsed | Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    $source = if ($archive -and $archive -match [regex]::Escape($selected.FileName)) { "Archive" } else { "Current" }
    $base = if ($source -eq "Archive") { $ArchiveUrl } else { $ReleaseUrl }

    return [PSCustomObject]@{
        FileName = $selected.FileName
        Version = $selected.Version
        ThreadSafety = $selected.ThreadSafety
        Architecture = $selected.Architecture
        Source = $source
        Url = "$base$($selected.FileName)"
    }
}

# ============================================================
# DOWNLOAD
# ============================================================

function Download-File([string]$Url, [string]$Destination) {
    Write-Info "Downloading $Url"
    $ProgressPreference = "SilentlyContinue"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 600
    } finally {
        $ProgressPreference = "Continue"
    }

    if (-not (Test-Path -LiteralPath $Destination)) { throw "Download failed." }
    if ((Get-Item -LiteralPath $Destination).Length -lt 10000) { throw "Downloaded ZIP is invalid or incomplete." }
    Write-OK "Download completed."
}

# ============================================================
# INSTALL
# ============================================================

function Install-Php {
    Write-Title "Install PHP"

    $requested = Read-Host "PHP version (7.2 / 7.2.34 / 8.5 / 8.5.0)"
    if ($requested -notmatch "^\d+\.\d+(?:\.\d+)?$") { Write-Err "Invalid version."; return }

    $architecture = Read-Host "Architecture [x64/x86] (default x64)"
    if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = "x64" }
    $architecture = $architecture.ToLower()
    if ($architecture -notin @("x64", "x86")) { Write-Err "Architecture must be x64 or x86."; return }

    Write-Host ""
    Write-Host "1. NTS - CLI/FastCGI"
    Write-Host "2. TS  - Apache/threaded"
    $choice = Read-Host "Thread Safety [1/2] (default 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    $threadSafety = if ($choice -eq "2") { "ts" } else { "nts" }

    try {
        $release = Find-PhpRelease -RequestedVersion $requested -ThreadSafety $threadSafety -Architecture $architecture
        Write-OK "Selected PHP $($release.Version)"
        Write-Host "File: $($release.FileName)"
        Write-Host "Source: $($release.Source)"
    } catch {
        Write-Err $_.Exception.Message
        return
    }

    $defaultInstall = Join-Path $VersionRoot $release.Version
    $installPath = Read-Host "Installation folder (default: $defaultInstall)"
    if ([string]::IsNullOrWhiteSpace($installPath)) { $installPath = $defaultInstall }
    $installPath = [Environment]::ExpandEnvironmentVariables($installPath)

    $confirm = Read-Host "Install PHP $($release.Version) here? [Y/n]"
    if ($confirm -match "^[Nn]$") { Write-Warn "Cancelled."; return }

    $zipPath = Join-Path $DownloadDir $release.FileName

    try {
        if (-not (Test-Path -LiteralPath $zipPath)) {
            Download-File $release.Url $zipPath
        } else {
            Write-OK "Using existing ZIP: $zipPath"
        }

        $tempPath = Join-Path $ManagerRoot ("temp-" + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null

        try {
            Write-Info "Extracting PHP..."
            Expand-Archive -LiteralPath $zipPath -DestinationPath $tempPath -Force

            $tempPhp = Get-ChildItem -LiteralPath $tempPath -Filter "php.exe" -File -Recurse -ErrorAction Stop | Select-Object -First 1
            if (-not $tempPhp) { throw "php.exe not found in ZIP." }

            $actual = Get-PhpVersion $tempPhp.FullName
            if (-not $actual) { throw "Downloaded PHP cannot be executed." }

            Write-OK "Downloaded executable reports PHP $actual"

            if (-not (Test-VersionMatch $actual $requested)) {
                throw "Version verification failed. Requested $requested, downloaded $actual."
            }

            if (Test-Path -LiteralPath $installPath) {
                $existingPhp = Join-Path $installPath "php.exe"
                if (Test-Path -LiteralPath $existingPhp) {
                    $existingVersion = Get-PhpVersion $existingPhp
                    Write-Warn "Existing PHP: $existingVersion"
                }

                $overwrite = Read-Host "Replace existing installation? [y/N]"
                if ($overwrite -notmatch "^[Yy]$") { Write-Warn "Cancelled."; return }
                Remove-Item -LiteralPath $installPath -Recurse -Force
            }

            New-Item -ItemType Directory -Path $installPath -Force | Out-Null
            Copy-Item -Path (Join-Path $tempPhp.Directory.FullName "*") -Destination $installPath -Recurse -Force

            $finalPhp = Join-Path $installPath "php.exe"
            $finalVersion = Get-PhpVersion $finalPhp
            if (-not $finalVersion) { throw "Installed PHP cannot be executed." }

            Write-OK "Installed PHP $finalVersion"

            Register-Php -PhpPath $finalPhp -Version $finalVersion -Architecture $architecture -ThreadSafety $threadSafety -InstallPath $installPath
            New-PhpWrapper -PhpPath $finalPhp -Version $finalVersion
            New-ComposerWrapper -PhpPath $finalPhp -Version $finalVersion
            New-ActivePhpHelper

            $makeActive = Read-Host "Make PHP $finalVersion active? [Y/n]"
            if ($makeActive -notmatch "^[Nn]$") {
                Set-Active -PhpPath $finalPhp -Version $finalVersion
                New-ActivePhpWrapper
                New-ActiveComposerWrapper
            }

            Add-ManagerToUserPath

            $deleteZip = Read-Host "Delete downloaded ZIP? [Y/n]"
            if ($deleteZip -notmatch "^[Nn]$") {
                Remove-Item -LiteralPath $zipPath -Force
                Write-OK "ZIP deleted."
            }

            Write-Host ""
            Write-OK "Installation completed."
            Write-Host "php$((Get-ShortVersion $finalVersion)) -v"
            Write-Host "cmp$((Get-ShortVersion $finalVersion)) --version"
            Write-Host "php -v"
            Write-Host "cmp --version"
        } finally {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Err $_.Exception.Message
    }
}

# ============================================================
# PATH MENU
# ============================================================

function Path-Menu {
    Write-Title "PATH Manager"
    Write-Host "1. Add Manager to User PATH"
    Write-Host "2. Refresh current PowerShell PATH"
    Write-Host "3. Show wrapper directory"
    Write-Host "4. Find php72/phpXX conflicts"
    Write-Host "5. Back"

    $choice = Read-Host "Select"

    switch ($choice) {
        "1" { Add-ManagerToUserPath }
        "2" {
            $user = [Environment]::GetEnvironmentVariable("Path", "User")
            $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $env:Path = "$user;$machine"
            Write-OK "Current PATH refreshed."
        }
        "3" { Write-Host $WrapperRoot }
        "4" {
            foreach ($cmd in @("php72","php80","php81","php82","php83","php84","php85","cmp72","cmp80","cmp81","cmp82","cmp83","cmp84","cmp85","php","cmp")) {
                $found = @(Find-CommandConflicts $cmd)
                if ($found.Count -gt 0) {
                    Write-Host "$cmd :" -ForegroundColor Cyan
                    $found | ForEach-Object { Write-Host "  $_" }
                }
            }
        }
    }
}

# ============================================================
# SYSTEM INFO
# ============================================================

function Show-SystemInfo {
    Write-Title "System Information"
    Write-Host "OS          : $([Environment]::OSVersion.VersionString)"
    Write-Host "PowerShell  : $($PSVersionTable.PSVersion)"
    Write-Host "Architecture: $env:PROCESSOR_ARCHITECTURE"
    Write-Host "Manager     : $ManagerRoot"
    Write-Host "Versions    : $VersionRoot"
    Write-Host "Wrappers    : $WrapperRoot"
    Show-ActivePhp
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {
    while ($true) {
        Write-Title "PHP Version Manager"
        Write-Host "Manager: $ManagerRoot"
        Write-Host ""
        Write-Host "1. List installed PHP versions"
        Write-Host "2. Install / download PHP"
        Write-Host "3. Switch active PHP"
        Write-Host "4. Show active PHP"
        Write-Host "5. Remove PHP"
        Write-Host "6. Verify phpXX / cmpXX / php / cmp"
        Write-Host "7. Rebuild wrappers"
        Write-Host "8. PATH manager"
        Write-Host "9. System information"
        Write-Host "10. Exit"

        $choice = Read-Host "Select"

        switch ($choice) {
            "1" { Show-InstalledVersions }
            "2" { Install-Php }
            "3" { Switch-ActivePhp }
            "4" { Show-ActivePhp }
            "5" { Remove-Php }
            "6" { Verify-Commands }
            "7" { Rebuild-Wrappers }
            "8" { Path-Menu }
            "9" { Show-SystemInfo }
            "10" { return }
            default { Write-Warn "Invalid option." }
        }

        Write-Host ""
        Read-Host "Press ENTER to continue" | Out-Null
    }
}

# ============================================================
# START
# ============================================================

Initialize-Manager
New-ActivePhpHelper
New-ActivePhpWrapper
New-ActiveComposerWrapper
Add-ManagerToUserPath
Rebuild-Wrappers
Show-MainMenu
