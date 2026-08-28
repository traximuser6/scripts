#requires -Version 5.1

<#
.SYNOPSIS
    Dynamic PHP Version Manager for Windows

.DESCRIPTION
    Features:

      php72  -> PHP 7.2.x
      php80  -> PHP 8.0.x
      php81  -> PHP 8.1.x
      php82  -> PHP 8.2.x
      php83  -> PHP 8.3.x
      php84  -> PHP 8.4.x
      php85  -> PHP 8.5.x

      cmp72  -> Composer using PHP 7.2.x
      cmp85  -> Composer using PHP 8.5.x

      php    -> Active PHP
      cmp    -> Composer using Active PHP

    PHP may be installed anywhere:
      C:\wamp64\bin\php\php8.2.29
      D:\PHP\8.2
      C:\tools\php85
      etc.

    The manager stores the exact php.exe path in registry.json.

    Supports:
      - Detect existing PHP installations
      - WAMP
      - XAMPP
      - C:\PHP
      - Custom paths
      - Install PHP 7.2+ from official Windows releases
      - Current releases
      - Archived releases
      - Exact versions
      - Branch versions
      - x64 / x86
      - NTS / TS
      - Composer wrappers
      - Active PHP switching
      - phpXX wrappers
      - cmpXX wrappers
      - PATH management
      - ZIP cleanup
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION
# ============================================================

$ManagerRoot       = Join-Path $env:USERPROFILE ".php-manager"
$RegistryFile      = Join-Path $ManagerRoot "registry.json"
$DownloadDir       = Join-Path $ManagerRoot "downloads"
$VersionRoot       = Join-Path $ManagerRoot "versions"
$WrapperRoot       = Join-Path $ManagerRoot "bin"
$ActiveFile        = Join-Path $ManagerRoot "active.json"

$ReleaseUrl        = "https://windows.php.net/downloads/releases/"
$ArchiveUrl        = "https://windows.php.net/downloads/releases/archives/"

# ============================================================
# UI
# ============================================================

function Write-Title {
    param([string]$Text)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[!] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "[ERROR] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "[INFO] $Text" -ForegroundColor Gray
}

# ============================================================
# INITIALIZATION
# ============================================================

function Initialize-Manager {

    $directories = @(
        $ManagerRoot,
        $DownloadDir,
        $VersionRoot,
        $WrapperRoot
    )

    foreach ($dir in $directories) {

        if (-not (Test-Path $dir)) {

            New-Item `
                -ItemType Directory `
                -Path $dir `
                -Force |
                Out-Null
        }
    }

    if (-not (Test-Path $RegistryFile)) {

        $registry = @{
            installations = @()
        }

        $registry |
            ConvertTo-Json -Depth 20 |
            Set-Content `
                -Path $RegistryFile `
                -Encoding UTF8
    }

    if (-not (Test-Path $ActiveFile)) {

        @{
            activePath    = $null
            activeVersion = $null
        } |
            ConvertTo-Json -Depth 10 |
            Set-Content `
                -Path $ActiveFile `
                -Encoding UTF8
    }
}

# ============================================================
# REGISTRY
# ============================================================

function Get-Registry {

    if (-not (Test-Path $RegistryFile)) {
        Initialize-Manager
    }

    try {

        $raw = Get-Content `
            -Path $RegistryFile `
            -Raw

        if ([string]::IsNullOrWhiteSpace($raw)) {

            return [PSCustomObject]@{
                installations = @()
            }
        }

        $data = $raw | ConvertFrom-Json

        if ($null -eq $data.installations) {

            $data |
                Add-Member `
                    -MemberType NoteProperty `
                    -Name installations `
                    -Value @()
        }

        return $data
    }
    catch {

        Write-Warn "Registry is invalid. Recreating."

        @{
            installations = @()
        } |
            ConvertTo-Json -Depth 20 |
            Set-Content `
                -Path $RegistryFile `
                -Encoding UTF8

        return [PSCustomObject]@{
            installations = @()
        }
    }
}

function Save-Registry {
    param($Registry)

    $Registry |
        ConvertTo-Json -Depth 20 |
        Set-Content `
            -Path $RegistryFile `
            -Encoding UTF8
}

# ============================================================
# ACTIVE PHP
# ============================================================

function Get-Active {

    if (-not (Test-Path $ActiveFile)) {

        return [PSCustomObject]@{
            activePath    = $null
            activeVersion = $null
        }
    }

    try {

        $raw = Get-Content `
            -Path $ActiveFile `
            -Raw

        if ([string]::IsNullOrWhiteSpace($raw)) {

            return [PSCustomObject]@{
                activePath    = $null
                activeVersion = $null
            }
        }

        return $raw | ConvertFrom-Json
    }
    catch {

        return [PSCustomObject]@{
            activePath    = $null
            activeVersion = $null
        }
    }
}

function Set-Active {
    param(
        [string]$PhpPath,
        [string]$Version
    )

    @{
        activePath    = $PhpPath
        activeVersion = $Version
        updatedAt     = (Get-Date).ToString("o")
    } |
        ConvertTo-Json -Depth 10 |
        Set-Content `
            -Path $ActiveFile `
            -Encoding UTF8

    Write-OK "Active PHP: $Version"
}

# ============================================================
# VERSION HELPERS
# ============================================================

function Get-ShortVersion {
    param([string]$Version)

    if ($Version -match "^(\d+)\.(\d+)") {

        return "$($Matches[1])$($Matches[2])"
    }

    return $null
}

function Test-VersionMatch {
    param(
        [string]$Actual,
        [string]$Requested
    )

    try {

        $actualVersion = [version]$Actual

        if ($Requested -match "^\d+\.\d+$") {

            $p = $Requested.Split(".")

            return (
                $actualVersion.Major -eq [int]$p[0] -and
                $actualVersion.Minor -eq [int]$p[1]
            )
        }

        if ($Requested -match "^\d+\.\d+\.\d+$") {

            return (
                $actualVersion -eq [version]$Requested
            )
        }
    }
    catch {
        return $false
    }

    return $false
}

function Get-PhpVersionFromExecutable {
    param([string]$PhpExe)

    if (-not (Test-Path $PhpExe)) {
        return $null
    }

    try {

        $output = & $PhpExe -r "echo PHP_VERSION;" 2>$null

        if ($LASTEXITCODE -eq 0 -and $output) {

            return ([string]$output).Trim()
        }
    }
    catch {
        return $null
    }

    return $null
}

# ============================================================
# PHP DISCOVERY
# ============================================================

function Find-PhpExecutables {

    $results = New-Object System.Collections.Generic.List[object]

    $registry = Get-Registry

    foreach ($item in @($registry.installations)) {

        if ($null -eq $item) {
            continue
        }

        $path = [string]$item.path

        if (-not (Test-Path $path)) {
            continue
        }

        $actual = Get-PhpVersionFromExecutable $path

        if ($actual) {

            $exists = $results |
                Where-Object {
                    $_.Path -ieq $path
                }

            if (-not $exists) {

                $results.Add(
                    [PSCustomObject]@{
                        Version = $actual
                        Path    = $path
                        Source  = "Registry"
                    }
                )
            }
        }
    }

    # --------------------------------------------------------
    # Common PHP locations
    # --------------------------------------------------------

    $commonRoots = @(
        "C:\PHP",
        "C:\php",
        "C:\wamp64\bin\php",
        "C:\wamp\bin\php",
        "C:\xampp\php",
        "C:\tools\php",
        $VersionRoot
    )

    # --------------------------------------------------------
    # Also scan PATH directories
    # --------------------------------------------------------

    $pathEntries = @()

    foreach ($scope in @("User", "Machine")) {

        try {

            $p = [Environment]::GetEnvironmentVariable(
                "Path",
                $scope
            )

            if ($p) {

                $pathEntries += (
                    $p -split ";" |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_)
                    }
                )
            }
        }
        catch {}
    }

    $commonRoots += $pathEntries

    $commonRoots = @(
        $commonRoots |
        Where-Object {
            $_ -and (Test-Path $_)
        } |
        Sort-Object -Unique
    )

    foreach ($root in $commonRoots) {

        try {

            $files = Get-ChildItem `
                -Path $root `
                -Filter "php.exe" `
                -File `
                -Recurse `
                -ErrorAction SilentlyContinue

            foreach ($file in $files) {

                $actual = Get-PhpVersionFromExecutable `
                    $file.FullName

                if (-not $actual) {
                    continue
                }

                $exists = $results |
                    Where-Object {
                        $_.Path -ieq $file.FullName
                    }

                if (-not $exists) {

                    $results.Add(
                        [PSCustomObject]@{
                            Version = $actual
                            Path    = $file.FullName
                            Source  = "Scan"
                        }
                    )
                }
            }
        }
        catch {}
    }

    return @(
        $results |
        Sort-Object `
            @{Expression = {
                try {
                    [version]$_.Version
                }
                catch {
                    [version]"0.0.0"
                }
            }} `
            -Descending
    )
}

# ============================================================
# REGISTER PHP
# ============================================================

function Register-Php {
    param(
        [string]$PhpPath,
        [string]$Version,
        [string]$Architecture,
        [string]$ThreadSafety,
        [string]$InstallPath
    )

    $registry = Get-Registry

    $entries = @(
        $registry.installations |
        Where-Object {
            $_.path -ine $PhpPath
        }
    )

    $entry = [PSCustomObject]@{
        version      = $Version
        path         = $PhpPath
        installPath  = $InstallPath
        architecture = $Architecture
        threadSafety = $ThreadSafety
        registeredAt = (Get-Date).ToString("o")
    }

    $registry.installations = @(
        $entries + $entry
    )

    Save-Registry $registry
}

# ============================================================
# SHOW INSTALLED
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

        $isActive = (
            $active.activePath -and
            ($php.Path -ieq $active.activePath)
        )

        Write-Host ""

        if ($isActive) {

            Write-Host "[ACTIVE] PHP $($php.Version)" `
                -ForegroundColor Green
        }
        else {

            Write-Host "PHP $($php.Version)" `
                -ForegroundColor Cyan
        }

        Write-Host "  Path   : $($php.Path)" `
            -ForegroundColor Gray

        Write-Host "  Source : $($php.Source)" `
            -ForegroundColor Gray

        $short = Get-ShortVersion $php.Version

        if ($short) {

            Write-Host "  Command: php$short" `
                -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

# ============================================================
# OFFICIAL WINDOWS PHP RELEASES
# ============================================================

function Get-WebText {
    param([string]$Url)

    Write-Info "Fetching: $Url"

    try {

        $ProgressPreference = "SilentlyContinue"

        $response = Invoke-WebRequest `
            -Uri $Url `
            -UseBasicParsing `
            -TimeoutSec 60

        $ProgressPreference = "Continue"

        return $response.Content
    }
    catch {

        throw "Unable to fetch $Url : $($_.Exception.Message)"
    }
}

function Get-ReleaseFiles {
    param(
        [string]$Html
    )

    $pattern = 'php-\d+\.\d+\.\d+-(?:nts-)?Win32-[^"\s<>]+-(?:x64|x86)\.zip'

    $matches = [regex]::Matches(
        $Html,
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    return @(
        $matches |
        ForEach-Object {
            $_.Value
        } |
        Sort-Object -Unique
    )
}

function Parse-PhpZipFile {
    param([string]$FileName)

    if ($FileName -match '^php-(\d+\.\d+\.\d+)-(nts-)?Win32-.*-(x64|x86)\.zip$') {

        return [PSCustomObject]@{
            FileName    = $FileName
            Version     = $Matches[1]
            ThreadSafety = if ($Matches[2]) {
                "nts"
            }
            else {
                "ts"
            }
            Architecture = $Matches[3]
        }
    }

    return $null
}

function Find-PhpRelease {

    param(
        [Parameter(Mandatory)]
        [string]$RequestedVersion,

        [ValidateSet("nts", "ts")]
        [string]$ThreadSafety = "nts",

        [ValidateSet("x64", "x86")]
        [string]$Architecture = "x64"
    )

    Write-Info "Searching official PHP Windows releases..."

    $releaseHtml = $null
    $archiveHtml = $null

    try {
        $releaseHtml = Get-WebText $ReleaseUrl
    }
    catch {
        Write-Warn "Current release list unavailable."
    }

    try {
        $archiveHtml = Get-WebText $ArchiveUrl
    }
    catch {
        Write-Warn "Archive release list unavailable."
    }

    $allFiles = @()

    if ($releaseHtml) {

        $allFiles += Get-ReleaseFiles `
            -Html $releaseHtml
    }

    if ($archiveHtml) {

        $allFiles += Get-ReleaseFiles `
            -Html $archiveHtml
    }

    $allFiles = @(
        $allFiles |
        Sort-Object -Unique
    )

    $parsed = @()

    foreach ($file in $allFiles) {

        $info = Parse-PhpZipFile $file

        if ($null -eq $info) {
            continue
        }

        if ($info.Architecture -ne $Architecture) {
            continue
        }

        if ($info.ThreadSafety -ne $ThreadSafety) {
            continue
        }

        $parsed += $info
    }

    if ($RequestedVersion -match "^\d+\.\d+$") {

        $parsed = @(
            $parsed |
            Where-Object {
                $_.Version -like "$RequestedVersion.*"
            }
        )
    }
    else {

        $parsed = @(
            $parsed |
            Where-Object {
                $_.Version -eq $RequestedVersion
            }
        )
    }

    if ($parsed.Count -eq 0) {

        throw @"
No official Windows PHP build found.

Requested:
  Version     : $RequestedVersion
  Architecture: $Architecture
  ThreadSafety: $ThreadSafety

The requested combination may not exist officially.
Try:
  - x64 instead of x86
  - NTS instead of TS
  - another patch version
"@
    }

    $selected = $parsed |
        Sort-Object {
            try {
                [version]$_.Version
            }
            catch {
                [version]"0.0.0"
            }
        } -Descending |
        Select-Object -First 1

    $source = "Current"

    if ($archiveHtml -and
        ($archiveHtml -match [regex]::Escape($selected.FileName))) {

        $source = "Archive"
    }

    $baseUrl = if ($source -eq "Archive") {
        $ArchiveUrl
    }
    else {
        $ReleaseUrl
    }

    return [PSCustomObject]@{
        FileName      = $selected.FileName
        Version       = $selected.Version
        ThreadSafety  = $selected.ThreadSafety
        Architecture  = $selected.Architecture
        Source        = $source
        Url           = "$baseUrl$($selected.FileName)"
    }
}

# ============================================================
# DOWNLOAD
# ============================================================

function Download-File {
    param(
        [string]$Url,
        [string]$Destination
    )

    Write-Info "Downloading:"
    Write-Host $Url -ForegroundColor Gray
    Write-Host ""

    try {

        $ProgressPreference = "SilentlyContinue"

        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $Destination `
            -UseBasicParsing `
            -TimeoutSec 600

        $ProgressPreference = "Continue"

        if (-not (Test-Path $Destination)) {

            throw "Downloaded file was not found."
        }

        $size = (Get-Item $Destination).Length

        if ($size -lt 10000) {

            throw "Downloaded file looks invalid or incomplete."
        }

        Write-OK "Download completed."
    }
    catch {

        throw "Download failed: $($_.Exception.Message)"
    }
}

# ============================================================
# WRAPPER CONTENT
# ============================================================

function Escape-BatchValue {
    param([string]$Value)

    return $Value.Replace("%", "%%")
}

function New-PhpWrapper {
    param(
        [string]$PhpPath,
        [string]$Version
    )

    $short = Get-ShortVersion $Version

    if (-not $short) {
        throw "Could not generate short version for $Version"
    }

    $wrapper = Join-Path `
        $WrapperRoot `
        "php$short.bat"

    $safePath = Escape-BatchValue $PhpPath

    $content = @"
@echo off
setlocal

set "PHP_EXE=$safePath"

if not exist "%PHP_EXE%" (
    echo.
    echo ERROR: PHP $Version is no longer available.
    echo.
    echo Expected:
    echo %PHP_EXE%
    echo.
    echo Run PHP Manager and rebuild wrappers.
    exit /b 1
)

"%PHP_EXE%" %*

endlocal
"@

    # Detect conflicting wrapper
    if (Test-Path $wrapper) {

        $old = Get-Content `
            -Path $wrapper `
            -Raw `
            -ErrorAction SilentlyContinue

        if ($old -and
            ($old -notmatch [regex]::Escape($PhpPath))) {

            Write-Warn "Replacing existing conflicting wrapper:"
            Write-Host $wrapper
        }
    }

    Set-Content `
        -Path $wrapper `
        -Value $content `
        -Encoding ASCII

    Write-OK "Created php$short.bat"
}

# ============================================================
# ACTIVE PHP WRAPPER
# ============================================================

function New-ActivePhpWrapper {

    $wrapper = Join-Path `
        $WrapperRoot `
        "php.bat"

    $activeFileForBatch = Escape-BatchValue $ActiveFile

    $content = @"
@echo off
setlocal

set "ACTIVE_FILE=$activeFileForBatch"

if not exist "%ACTIVE_FILE%" (
    echo ERROR: Active PHP configuration not found.
    echo Run PHP Manager and select an active PHP version.
    exit /b 1
)

for /f "usebackq tokens=2 delims=:," %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$j=Get-Content -Raw -LiteralPath '%ActiveFile%'^|ConvertFrom-Json; if($j.activePath){$j.activePath}"`) do (
    set "PHP_EXE=%%~A"
)

if not defined PHP_EXE (
    echo ERROR: No active PHP selected.
    echo.
    echo Use PHP Manager and select:
    echo   Switch active PHP
    exit /b 1
)

if not exist "%PHP_EXE%" (
    echo ERROR: Active PHP executable not found:
    echo %PHP_EXE%
    exit /b 1
)

"%PHP_EXE%" %*

endlocal
"@

    Set-Content `
        -Path $wrapper `
        -Value $content `
        -Encoding ASCII

    Write-OK "Created active php command"
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

    foreach ($candidate in $candidates) {

        if (Test-Path $candidate) {

            return [PSCustomObject]@{
                Type = "phar"
                Path = $candidate
            }
        }
    }

    $command = Get-Command `
        composer `
        -ErrorAction SilentlyContinue

    if ($command) {

        $source = $command.Source

        if ($source -match "\.bat$") {

            # Try to find Composer PHAR referenced by composer.bat
            try {

                $bat = Get-Content `
                    -Path $source `
                    -Raw

                $pharMatch = [regex]::Match(
                    $bat,
                    '"([^"]*composer\.phar)"',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                )

                if ($pharMatch.Success) {

                    $phar = $pharMatch.Groups[1].Value

                    if (Test-Path $phar) {

                        return [PSCustomObject]@{
                            Type = "phar"
                            Path = $phar
                        }
                    }
                }
            }
            catch {}
        }

        return [PSCustomObject]@{
            Type = "command"
            Path = $source
        }
    }

    return $null
}

# ============================================================
# COMPOSER WRAPPER
# ============================================================

function New-ComposerWrapper {
    param(
        [string]$PhpPath,
        [string]$Version
    )

    $composer = Find-Composer

    if (-not $composer) {

        Write-Warn "Composer was not found."
        Write-Warn "cmp$((Get-ShortVersion $Version)) was not created."
        return
    }

    $short = Get-ShortVersion $Version

    $wrapper = Join-Path `
        $WrapperRoot `
        "cmp$short.bat"

    $safePhp = Escape-BatchValue $PhpPath
    $safeComposer = Escape-BatchValue $composer.Path

    if ($composer.Type -eq "phar") {

        $content = @"
@echo off
setlocal

set "PHP_EXE=$safePhp"
set "COMPOSER_PHAR=$safeComposer"

if not exist "%PHP_EXE%" (
    echo ERROR: PHP $Version not found:
    echo %PHP_EXE%
    exit /b 1
)

if not exist "%COMPOSER_PHAR%" (
    echo ERROR: Composer PHAR not found:
    echo %COMPOSER_PHAR%
    exit /b 1
)

"%PHP_EXE%" "%COMPOSER_PHAR%" %*

endlocal
"@
    }
    else {

        $content = @"
@echo off
setlocal

set "PHP_EXE=$safePhp"
set "COMPOSER_CMD=$safeComposer"

if not exist "%PHP_EXE%" (
    echo ERROR: PHP $Version not found:
    echo %PHP_EXE%
    exit /b 1
)

call "%COMPOSER_CMD%" %*

endlocal
"@
    }

    Set-Content `
        -Path $wrapper `
        -Value $content `
        -Encoding ASCII

    Write-OK "Created cmp$short.bat"
}

# ============================================================
# ACTIVE COMPOSER WRAPPER
# ============================================================

function New-ActiveComposerWrapper {

    $composer = Find-Composer

    if (-not $composer) {

        Write-Warn "Composer not found. cmp wrapper not created."
        return
    }

    $wrapper = Join-Path `
        $WrapperRoot `
        "cmp.bat"

    $safeActive = Escape-BatchValue $ActiveFile
    $safeComposer = Escape-BatchValue $composer.Path

    if ($composer.Type -eq "phar") {

        $content = @"
@echo off
setlocal

set "ACTIVE_FILE=$safeActive"
set "COMPOSER_PHAR=$safeComposer"

if not exist "%COMPOSER_PHAR%" (
    echo ERROR: Composer PHAR not found:
    echo %COMPOSER_PHAR%
    exit /b 1
)

for /f "usebackq tokens=2 delims=:," %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$j=Get-Content -Raw -LiteralPath '%ActiveFile%'^|ConvertFrom-Json; if($j.activePath){$j.activePath}"`) do (
    set "PHP_EXE=%%~A"
)

if not defined PHP_EXE (
    echo ERROR: No active PHP selected.
    exit /b 1
)

if not exist "%PHP_EXE%" (
    echo ERROR: Active PHP not found:
    echo %PHP_EXE%
    exit /b 1
)

"%PHP_EXE%" "%COMPOSER_PHAR%" %*

endlocal
"@
    }
    else {

        $content = @"
@echo off
setlocal

set "COMPOSER_CMD=$safeComposer"
set "ACTIVE_FILE=$safeActive"

if not exist "%COMPOSER_CMD%" (
    echo ERROR: Composer command not found.
    exit /b 1
)

for /f "usebackq tokens=2 delims=:," %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$j=Get-Content -Raw -LiteralPath '%ActiveFile%'^|ConvertFrom-Json; if($j.activePath){$j.activePath}"`) do (
    set "PHP_EXE=%%~A"
)

if defined PHP_EXE (
    set "PATH=%~dp0;%%PATH%%"
)

call "%COMPOSER_CMD%" %*

endlocal
"@
    }

    Set-Content `
        -Path $wrapper `
        -Value $content `
        -Encoding ASCII

    Write-OK "Created active cmp command"
}

# ============================================================
# REBUILD WRAPPERS
# ============================================================

function Rebuild-Wrappers {

    Write-Title "Rebuilding Wrappers"

    $versions = @(Find-PhpExecutables)

    if ($versions.Count -eq 0) {

        Write-Warn "No PHP installations found."
        return
    }

    foreach ($php in $versions) {

        $actual = Get-PhpVersionFromExecutable $php.Path

        if (-not $actual) {

            Write-Warn "Could not verify:"
            Write-Host $php.Path
            continue
        }

        Register-Php `
            -PhpPath $php.Path `
            -Version $actual `
            -Architecture "unknown" `
            -ThreadSafety "unknown" `
            -InstallPath (
                Split-Path `
                    $php.Path `
                    -Parent
            )

        New-PhpWrapper `
            -PhpPath $php.Path `
            -Version $actual

        New-ComposerWrapper `
            -PhpPath $php.Path `
            -Version $actual
    }

    New-ActivePhpWrapper
    New-ActiveComposerWrapper

    Write-OK "All wrappers rebuilt."
}

# ============================================================
# INSTALL PHP
# ============================================================

function Install-Php {

    Write-Title "Install PHP"

    $requested = Read-Host `
        "Enter PHP version (example: 8.4 or exact 8.4.15)"

    if ([string]::IsNullOrWhiteSpace($requested)) {
        Write-Err "PHP version is required."
        return
    }

    if ($requested -notmatch "^\d+\.\d+(?:\.\d+)?$") {

        Write-Err "Invalid version format."

        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  7.2"
        Write-Host "  7.2.34"
        Write-Host "  8.4"
        Write-Host "  8.4.15"

        return
    }

    # --------------------------------------------------------
    # Architecture
    # --------------------------------------------------------

    Write-Host ""

    $architecture = Read-Host `
        "Architecture [x64/x86] (default: x64)"

    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = "x64"
    }

    $architecture = $architecture.ToLower()

    if ($architecture -notin @("x64", "x86")) {

        Write-Err "Architecture must be x64 or x86."
        return
    }

    # --------------------------------------------------------
    # Thread Safety
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Thread Safety:" -ForegroundColor Cyan
    Write-Host "  1. NTS - CLI / FastCGI (recommended)"
    Write-Host "  2. TS  - Apache module / threaded SAPIs"

    $choice = Read-Host `
        "Choose [1/2] (default: 1)"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = "1"
    }

    if ($choice -eq "2") {
        $threadSafety = "ts"
    }
    else {
        $threadSafety = "nts"
    }

    # --------------------------------------------------------
    # Find release FIRST
    # --------------------------------------------------------

    try {

        Write-Host ""

        $release = Find-PhpRelease `
            -RequestedVersion $requested `
            -ThreadSafety $threadSafety `
            -Architecture $architecture

        Write-Host ""
        Write-OK "Selected PHP $($release.Version)"

        Write-Host "File:"
        Write-Host "  $($release.FileName)"

        Write-Host "Source:"
        Write-Host "  $($release.Source)"

        Write-Host "URL:"
        Write-Host "  $($release.Url)"

    }
    catch {

        Write-Err $_.Exception.Message
        return
    }

    # --------------------------------------------------------
    # Installation path
    # --------------------------------------------------------

    Write-Host ""

    $defaultInstall = Join-Path `
        $VersionRoot `
        $release.Version

    $installPath = Read-Host `
        "Installation folder (default: $defaultInstall)"

    if ([string]::IsNullOrWhiteSpace($installPath)) {
        $installPath = $defaultInstall
    }

    $installPath = `
        [Environment]::ExpandEnvironmentVariables(
            $installPath
        )

    # --------------------------------------------------------
    # Confirmation
    # --------------------------------------------------------

    Write-Host ""

    $confirm = Read-Host `
        "Install PHP $($release.Version) here? [Y/n]"

    if ($confirm -match "^[Nn]$") {

        Write-Warn "Installation cancelled."
        return
    }

    # --------------------------------------------------------
    # ZIP
    # --------------------------------------------------------

    $zipPath = Join-Path `
        $DownloadDir `
        $release.FileName

    try {

        if (Test-Path $zipPath) {

            Write-Warn "ZIP already exists:"
            Write-Host $zipPath

            $use = Read-Host `
                "Use existing ZIP? [Y/n]"

            if ($use -match "^[Nn]$") {

                Remove-Item `
                    -Path $zipPath `
                    -Force

                Download-File `
                    -Url $release.Url `
                    -Destination $zipPath
            }
        }
        else {

            Download-File `
                -Url $release.Url `
                -Destination $zipPath
        }

        # ----------------------------------------------------
        # Temporary extraction
        # ----------------------------------------------------

        $tempPath = Join-Path `
            $ManagerRoot `
            ("temp-" + [guid]::NewGuid().ToString())

        New-Item `
            -ItemType Directory `
            -Path $tempPath `
            -Force |
            Out-Null

        try {

            Write-Info "Extracting PHP..."

            Expand-Archive `
                -Path $zipPath `
                -DestinationPath $tempPath `
                -Force

            $tempPhp = Get-ChildItem `
                -Path $tempPath `
                -Filter "php.exe" `
                -File `
                -Recurse `
                -ErrorAction Stop |
                Select-Object -First 1

            if (-not $tempPhp) {

                throw "php.exe was not found inside the downloaded ZIP."
            }

            $actualVersion = Get-PhpVersionFromExecutable `
                $tempPhp.FullName

            if (-not $actualVersion) {

                throw "Extracted PHP could not be executed."
            }

            Write-OK "Extracted PHP version: $actualVersion"

            # ------------------------------------------------
            # Verify requested branch/exact version
            # ------------------------------------------------

            if (-not (
                Test-VersionMatch `
                    -Actual $actualVersion `
                    -Requested $requested
            )) {

                throw @"
PHP version verification failed.

Requested:
  $requested

Downloaded:
  $actualVersion
"@
            }

            Write-OK "Version verification passed."

            # ------------------------------------------------
            # Existing installation
            # ------------------------------------------------

            if (Test-Path $installPath) {

                $existingPhp = Join-Path `
                    $installPath `
                    "php.exe"

                if (Test-Path $existingPhp) {

                    $existingVersion = `
                        Get-PhpVersionFromExecutable `
                            $existingPhp

                    Write-Warn `
                        "Existing PHP found: $existingVersion"

                    $overwrite = Read-Host `
                        "Replace existing installation? [y/N]"

                    if ($overwrite -notmatch "^[Yy]$") {

                        Write-Warn "Installation cancelled."
                        return
                    }
                }

                Remove-Item `
                    -Path $installPath `
                    -Recurse `
                    -Force
            }

            # ------------------------------------------------
            # Create installation directory
            # ------------------------------------------------

            New-Item `
                -ItemType Directory `
                -Path $installPath `
                -Force |
                Out-Null

            Write-Info "Installing to:"
            Write-Host $installPath -ForegroundColor Gray

            $sourceRoot = $tempPhp.Directory.FullName

            Copy-Item `
                -Path (Join-Path $sourceRoot "*") `
                -Destination $installPath `
                -Recurse `
                -Force

            $finalPhp = Join-Path `
                $installPath `
                "php.exe"

            if (-not (Test-Path $finalPhp)) {

                throw "Installation failed: php.exe missing."
            }

            $finalVersion = Get-PhpVersionFromExecutable `
                $finalPhp

            if (-not $finalVersion) {

                throw "Installed PHP could not be executed."
            }

            Write-OK "Installed PHP $finalVersion"

            # ------------------------------------------------
            # Register exact mapping
            # ------------------------------------------------

            Register-Php `
                -PhpPath $finalPhp `
                -Version $finalVersion `
                -Architecture $architecture `
                -ThreadSafety $threadSafety `
                -InstallPath $installPath

            # ------------------------------------------------
            # Create version wrappers
            # ------------------------------------------------

            New-PhpWrapper `
                -PhpPath $finalPhp `
                -Version $finalVersion

            New-ComposerWrapper `
                -PhpPath $finalPhp `
                -Version $finalVersion

            # ------------------------------------------------
            # Active?
            # ------------------------------------------------

            Write-Host ""

            $makeActive = Read-Host `
                "Make PHP $finalVersion the active 'php' command? [Y/n]"

            if ($makeActive -notmatch "^[Nn]$") {

                Set-Active `
                    -PhpPath $finalPhp `
                    -Version $finalVersion

                New-ActivePhpWrapper
                New-ActiveComposerWrapper
            }

            # ------------------------------------------------
            # Delete ZIP
            # ------------------------------------------------

            Write-Host ""

            $deleteZip = Read-Host `
                "Delete downloaded ZIP file? [Y/n]"

            if ($deleteZip -notmatch "^[Nn]$") {

                Remove-Item `
                    -Path $zipPath `
                    -Force

                Write-OK "ZIP removed."
            }
            else {

                Write-Info "ZIP kept:"
                Write-Host $zipPath
            }

            Write-Host ""
            Write-OK "PHP $finalVersion installation completed."

            Write-Host ""
            Write-Host "Commands:" -ForegroundColor Cyan

            $short = Get-ShortVersion $finalVersion

            Write-Host "  php$short -v"
            Write-Host "  cmp$short --version"
            Write-Host "  php -v"
            Write-Host "  cmp --version"

        }
        finally {

            if (Test-Path $tempPath) {

                Remove-Item `
                    -Path $tempPath `
                    -Recurse `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }
    catch {

        Write-Err $_.Exception.Message
    }
}

# ============================================================
# SWITCH ACTIVE PHP
# ============================================================

function Switch-ActivePhp {

    Write-Title "Switch Active PHP"

    $versions = @(Find-PhpExecutables)

    if ($versions.Count -eq 0) {

        Write-Warn "No PHP installations found."
        return
    }

    for ($i = 0; $i -lt $versions.Count; $i++) {

        $php = $versions[$i]

        Write-Host ""
        Write-Host "[$($i + 1)] PHP $($php.Version)" `
            -ForegroundColor Cyan

        Write-Host "    $($php.Path)" `
            -ForegroundColor Gray
    }

    Write-Host ""

    $selection = Read-Host `
        "Select PHP number"

    if ($selection -notmatch "^\d+$") {
        Write-Err "Invalid selection."
        return
    }

    $index = [int]$selection - 1

    if (
        $index -lt 0 -or
        $index -ge $versions.Count
    ) {

        Write-Err "Invalid selection."
        return
    }

    $selected = $versions[$index]

    Set-Active `
        -PhpPath $selected.Path `
        -Version $selected.Version

    New-ActivePhpWrapper
    New-ActiveComposerWrapper

    Write-Host ""
    Write-OK "php now points to PHP $($selected.Version)"
    Write-OK "cmp now uses PHP $($selected.Version)"

    Write-Host ""
    Write-Host "Run:"
    Write-Host "  php -v"
    Write-Host "  cmp --version"
}

# ============================================================
# SHOW ACTIVE PHP
# ============================================================

function Show-ActivePhp {

    Write-Title "Active PHP"

    $active = Get-Active

    if (
        -not $active.activePath -or
        [string]::IsNullOrWhiteSpace(
            [string]$active.activePath
        )
    ) {

        Write-Warn "No active PHP selected."

        Write-Host ""
        Write-Host "Use:"
        Write-Host "  Switch active PHP"

        return
    }

    Write-Host "Version:" -ForegroundColor Cyan
    Write-Host "  $($active.activeVersion)"

    Write-Host ""
    Write-Host "Path:" -ForegroundColor Cyan
    Write-Host "  $($active.activePath)"

    Write-Host ""

    if (Test-Path $active.activePath) {

        $actual = Get-PhpVersionFromExecutable `
            $active.activePath

        if ($actual) {

            Write-OK `
                "Actual executable reports PHP $actual"
        }
        else {

            Write-Err "Active PHP cannot be executed."
        }
    }
    else {

        Write-Err "Active PHP executable does not exist."
    }
}

# ============================================================
# VERIFY COMMAND
# ============================================================

function Verify-Command {

    Write-Title "Verify PHP Commands"

    Write-Host "Examples:"
    Write-Host "  php72"
    Write-Host "  php82"
    Write-Host "  php"
    Write-Host "  cmp72"
    Write-Host ""

    $command = Read-Host "Enter command"

    if ([string]::IsNullOrWhiteSpace($command)) {
        return
    }

    $cmd = Get-Command `
        $command `
        -ErrorAction SilentlyContinue

    if (-not $cmd) {

        Write-Err "'$command' was not found."

        Write-Host ""
        Write-Host "Wrapper directory:"
        Write-Host "  $WrapperRoot"

        Write-Host ""
        Write-Host "Run:"
        Write-Host "  PATH Manager"
        Write-Host "  Add to User PATH"

        return
    }

    Write-Host ""
    Write-Host "Resolved command:" `
        -ForegroundColor Cyan

    Write-Host "  $($cmd.Source)"

    Write-Host ""

    try {

        & $command --version
    }
    catch {

        Write-Err $_.Exception.Message
    }
}

# ============================================================
# REMOVE PHP
# ============================================================

function Remove-Php {

    Write-Title "Remove PHP"

    $versions = @(Find-PhpExecutables)

    if ($versions.Count -eq 0) {

        Write-Warn "No PHP installations found."
        return
    }

    for ($i = 0; $i -lt $versions.Count; $i++) {

        Write-Host ""
        Write-Host "[$($i + 1)] PHP $($versions[$i].Version)" `
            -ForegroundColor Cyan

        Write-Host "    $($versions[$i].Path)" `
            -ForegroundColor Gray
    }

    Write-Host ""

    $choice = Read-Host "Select version"

    if ($choice -notmatch "^\d+$") {
        return
    }

    $index = [int]$choice - 1

    if (
        $index -lt 0 -or
        $index -ge $versions.Count
    ) {

        Write-Err "Invalid selection."
        return
    }

    $selected = $versions[$index]

    $active = Get-Active

    if (
        $active.activePath -and
        ($active.activePath -ieq $selected.Path)
    ) {

        Write-Warn "This is the ACTIVE PHP."
        Write-Warn "Select another PHP before removing it."

        return
    }

    Write-Host ""
    Write-Host "Selected:"
    Write-Host "  PHP $($selected.Version)"
    Write-Host "  $($selected.Path)"

    $confirm = Read-Host `
        "Really remove this PHP? [y/N]"

    if ($confirm -notmatch "^[Yy]$") {
        return
    }

    try {

        $installPath = Split-Path `
            $selected.Path `
            -Parent

        Remove-Item `
            -Path $installPath `
            -Recurse `
            -Force

        Write-OK "Removed $installPath"

        $registry = Get-Registry

        $registry.installations = @(
            $registry.installations |
            Where-Object {
                $_.path -ine $selected.Path
            }
        )

        Save-Registry $registry

        $short = Get-ShortVersion `
            $selected.Version

        if ($short) {

            $phpWrapper = Join-Path `
                $WrapperRoot `
                "php$short.bat"

            $cmpWrapper = Join-Path `
                $WrapperRoot `
                "cmp$short.bat"

            if (Test-Path $phpWrapper) {

                Remove-Item `
                    $phpWrapper `
                    -Force
            }

            if (Test-Path $cmpWrapper) {

                Remove-Item `
                    $cmpWrapper `
                    -Force
            }
        }

        Write-OK "Registry and wrappers updated."
    }
    catch {

        Write-Err $_.Exception.Message
    }
}

# ============================================================
# PATH
# ============================================================

function Add-ToPath {

    param(
        [ValidateSet("User", "Machine")]
        [string]$Scope = "User"
    )

    $current = [Environment]::GetEnvironmentVariable(
        "Path",
        $Scope
    )

    $entries = @()

    if ($current) {

        $entries = @(
            $current -split ";" |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            }
        )
    }

    $already = $entries |
        Where-Object {
            $_.TrimEnd("\") -ieq
            $WrapperRoot.TrimEnd("\")
        }

    if ($already) {

        Write-Warn `
            "$WrapperRoot is already in $Scope PATH."
    }
    else {

        $newPath = (
            @($entries) + $WrapperRoot
        ) -join ";"

        try {

            [Environment]::SetEnvironmentVariable(
                "Path",
                $newPath,
                $Scope
            )

            Write-OK `
                "Added $WrapperRoot to $Scope PATH."
        }
        catch {

            Write-Err $_.Exception.Message

            if ($Scope -eq "Machine") {

                Write-Warn `
                    "Run PowerShell as Administrator."
            }

            return
        }
    }

    # --------------------------------------------------------
    # Update CURRENT PowerShell session
    # --------------------------------------------------------

    try {

        $userPath = [Environment]::GetEnvironmentVariable(
            "Path",
            "User"
        )

        $machinePath = [Environment]::GetEnvironmentVariable(
            "Path",
            "Machine"
        )

        $parts = @()

        if ($machinePath) {
            $parts += $machinePath
        }

        if ($userPath) {
            $parts += $userPath
        }

        $env:Path = (
            $parts -join ";"
        )
    }
    catch {}

    Write-OK "Current PowerShell PATH refreshed."

    Write-Host ""
    Write-Host "You can now try:"
    Write-Host "  php72 -v"
    Write-Host "  php85 -v"
    Write-Host "  php -v"
    Write-Host "  cmp72 --version"
}

function Path-Menu {

    Write-Title "PATH Manager"

    Write-Host "1. Add to User PATH"
    Write-Host "2. Add to Machine PATH"
    Write-Host "3. Refresh current PowerShell PATH"
    Write-Host "4. Show wrapper path"
    Write-Host "5. Back"

    Write-Host ""

    $choice = Read-Host "Select"

    switch ($choice) {

        "1" {
            Add-ToPath -Scope User
        }

        "2" {
            Add-ToPath -Scope Machine
        }

        "3" {

            $user = [Environment]::GetEnvironmentVariable(
                "Path",
                "User"
            )

            $machine = [Environment]::GetEnvironmentVariable(
                "Path",
                "Machine"
            )

            $env:Path = "$machine;$user"

            Write-OK "Current PowerShell PATH refreshed."
        }

        "4" {

            Write-Host ""
            Write-Host "Wrapper directory:"
            Write-Host $WrapperRoot
        }

        "5" {
            return
        }
    }
}

# ============================================================
# SYSTEM INFO
# ============================================================

function Show-SystemInfo {

    Write-Title "System Information"

    Write-Host "OS:"
    Write-Host "  $([Environment]::OSVersion.VersionString)"

    Write-Host ""
    Write-Host "PowerShell:"
    Write-Host "  $($PSVersionTable.PSVersion)"

    Write-Host ""
    Write-Host "Architecture:"
    Write-Host "  $env:PROCESSOR_ARCHITECTURE"

    Write-Host ""
    Write-Host "Manager:"
    Write-Host "  $ManagerRoot"

    Write-Host ""
    Write-Host "Versions:"
    Write-Host "  $VersionRoot"

    Write-Host ""
    Write-Host "Wrappers:"
    Write-Host "  $WrapperRoot"

    Write-Host ""

    Show-ActivePhp
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {

    while ($true) {

        Write-Title "PHP Version Manager"

        Write-Host "Manager: $ManagerRoot" `
            -ForegroundColor Gray

        Write-Host ""

        Write-Host "1. List installed PHP versions"
        Write-Host "2. Install / download PHP version"
        Write-Host "3. Switch active PHP"
        Write-Host "4. Show active PHP"
        Write-Host "5. Remove PHP version"
        Write-Host "6. Verify phpXX / php / cmpXX"
        Write-Host "7. Rebuild phpXX / cmpXX wrappers"
        Write-Host "8. PATH manager"
        Write-Host "9. System information"
        Write-Host "10. Exit"

        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice) {

            "1" {
                Show-InstalledVersions
            }

            "2" {
                Install-Php
            }

            "3" {
                Switch-ActivePhp
            }

            "4" {
                Show-ActivePhp
            }

            "5" {
                Remove-Php
            }

            "6" {
                Verify-Command
            }

            "7" {
                Rebuild-Wrappers
            }

            "8" {
                Path-Menu
            }

            "9" {
                Show-SystemInfo
            }

            "10" {

                Write-Host ""
                Write-Host "Goodbye." `
                    -ForegroundColor Cyan

                return
            }

            default {

                Write-Warn "Invalid option."
            }
        }

        Write-Host ""
        Read-Host "Press ENTER to continue"
    }
}

# ============================================================
# START
# ============================================================

Initialize-Manager

# Always ensure active wrappers exist
New-ActivePhpWrapper
New-ActiveComposerWrapper

Show-MainMenu