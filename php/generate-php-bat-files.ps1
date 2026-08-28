#requires -Version 5.1

<#
.SYNOPSIS
    Dynamic PHP Version Manager for Windows.

.DESCRIPTION
    - Detect installed PHP versions
    - Install PHP from official PHP Windows releases
    - Download latest patch for a requested major/minor branch
    - Install an exact PHP version when available
    - Create phpXX.bat wrappers
    - Create cmpXX.bat Composer wrappers
    - Verify the actual PHP version behind every wrapper
    - Manage User/System PATH
    - Optionally remove downloaded ZIP files

.EXAMPLES

    php-manager.ps1

    Interactive menu will be shown.

    Commands after installation:

        php84 -v
        php85 -v

        cmp84 install
        cmp85 update
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# CONFIGURATION
# ============================================================

$ManagerRoot = Join-Path $env:USERPROFILE ".php-manager"
$RegistryFile = Join-Path $ManagerRoot "registry.json"
$DownloadDir = Join-Path $ManagerRoot "downloads"
$DefaultInstallRoot = Join-Path $ManagerRoot "versions"

$WrapperRoot = Join-Path $ManagerRoot "bin"

# Official PHP Windows release directory
$OfficialReleaseUrl = "https://www.php.net/~windows/releases/"

# ============================================================
# COLORS / UI
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
        $DefaultInstallRoot,
        $WrapperRoot
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if (-not (Test-Path $RegistryFile)) {
        @{
            installations = @()
        } | ConvertTo-Json -Depth 10 |
            Set-Content -Path $RegistryFile -Encoding UTF8
    }
}

# ============================================================
# JSON REGISTRY
# ============================================================

function Get-Registry {

    if (-not (Test-Path $RegistryFile)) {
        Initialize-Manager
    }

    try {
        $content = Get-Content $RegistryFile -Raw

        if ([string]::IsNullOrWhiteSpace($content)) {
            return @{
                installations = @()
            }
        }

        $data = $content | ConvertFrom-Json

        if ($null -eq $data.installations) {
            $data | Add-Member -MemberType NoteProperty `
                -Name installations `
                -Value @()
        }

        return $data
    }
    catch {
        Write-Warn "Registry could not be read. Recreating it."

        @{
            installations = @()
        } | ConvertTo-Json -Depth 10 |
            Set-Content $RegistryFile -Encoding UTF8

        return @{
            installations = @()
        }
    }
}

function Save-Registry {
    param($Registry)

    $Registry | ConvertTo-Json -Depth 10 |
        Set-Content -Path $RegistryFile -Encoding UTF8
}

# ============================================================
# VERSION HELPERS
# ============================================================

function ConvertTo-VersionObject {
    param([string]$Version)

    try {
        return [version]$Version
    }
    catch {
        return $null
    }
}

function Get-PhpVersionFromExecutable {
    param([string]$PhpExe)

    if (-not (Test-Path $PhpExe)) {
        return $null
    }

    try {
        $output = & $PhpExe -r 'echo PHP_VERSION;' 2>$null

        if ($LASTEXITCODE -eq 0 -and $output) {
            return [string]$output
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-ShortVersion {
    param([string]$Version)

    $v = $Version -split "\."

    if ($v.Count -lt 2) {
        return $null
    }

    return "$($v[0])$($v[1])"
}

function Test-VersionMatch {
    param(
        [string]$Actual,
        [string]$Requested
    )

    try {
        $actualVersion = [version]$Actual

        if ($Requested -match "^\d+\.\d+$") {

            $parts = $Requested.Split(".")

            return (
                $actualVersion.Major -eq [int]$parts[0] -and
                $actualVersion.Minor -eq [int]$parts[1]
            )
        }

        if ($Requested -match "^\d+\.\d+\.\d+$") {
            return $actualVersion -eq [version]$Requested
        }
    }
    catch {
        return $false
    }

    return $false
}

# ============================================================
# INSTALLED PHP DISCOVERY
# ============================================================

function Find-PhpExecutables {

    $results = New-Object System.Collections.Generic.List[object]

    $registry = Get-Registry

    foreach ($item in @($registry.installations)) {

        if ($null -eq $item) {
            continue
        }

        $phpExe = $item.path

        if (Test-Path $phpExe) {

            $actual = Get-PhpVersionFromExecutable $phpExe

            if ($actual) {

                $results.Add([PSCustomObject]@{
                    Version = $actual
                    Path    = $phpExe
                    Source  = "Registry"
                })
            }
        }
    }

    # Also scan common locations
    $commonRoots = @(
        "C:\PHP",
        "C:\php",
        "C:\wamp64\bin\php",
        "C:\xampp\php",
        $DefaultInstallRoot
    )

    foreach ($root in $commonRoots) {

        if (-not (Test-Path $root)) {
            continue
        }

        $files = Get-ChildItem `
            -Path $root `
            -Filter "php.exe" `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue

        foreach ($file in $files) {

            $actual = Get-PhpVersionFromExecutable $file.FullName

            if ($actual) {

                $alreadyExists = $results | Where-Object {
                    $_.Path -eq $file.FullName
                }

                if (-not $alreadyExists) {

                    $results.Add([PSCustomObject]@{
                        Version = $actual
                        Path    = $file.FullName
                        Source  = "Scan"
                    })
                }
            }
        }
    }

    return $results |
        Sort-Object @{Expression = {
            try { [version]$_.Version }
            catch { [version]"0.0.0" }
        }} -Descending
}

# ============================================================
# DISPLAY INSTALLED VERSIONS
# ============================================================

function Show-InstalledVersions {

    Write-Title "Installed PHP Versions"

    $versions = @(Find-PhpExecutables)

    if ($versions.Count -eq 0) {

        Write-Warn "No PHP installations were found."
        return
    }

    $i = 1

    foreach ($php in $versions) {

        Write-Host ""
        Write-Host "[$i] PHP $($php.Version)" -ForegroundColor Green
        Write-Host "    $($php.Path)" -ForegroundColor Gray

        $short = Get-ShortVersion $php.Version

        if ($short) {
            Write-Host "    Command: php$short" -ForegroundColor Cyan
        }

        $i++
    }

    Write-Host ""
}

# ============================================================
# OFFICIAL RELEASE DATA
# ============================================================

function Get-OfficialReleaseData {

    Write-Info "Fetching official PHP Windows release list..."

    try {
        $response = Invoke-WebRequest `
            -Uri $OfficialReleaseUrl `
            -UseBasicParsing `
            -TimeoutSec 30

        return $response.Content
    }
    catch {
        throw "Unable to contact official PHP release server: $($_.Exception.Message)"
    }
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

    $html = Get-OfficialReleaseData

    # --------------------------------------------------------
    # Exact version requested:
    #
    # 8.4.25
    #
    # or branch:
    #
    # 8.4
    # --------------------------------------------------------

    $escaped = [regex]::Escape($RequestedVersion)

    $pattern = "php-$escaped(?:-nts)?-Win32-vs\d+-${Architecture}\.zip"

    $matches = [regex]::Matches(
        $html,
        $pattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($matches.Count -eq 0) {

        throw "No official Windows PHP build found for $RequestedVersion ($Architecture/$ThreadSafety)."
    }

    $files = @(
        $matches |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
    )

    # Prefer NTS or TS according to selection
    if ($ThreadSafety -eq "nts") {

        $selected = $files |
            Where-Object { $_ -match "-nts-" } |
            Select-Object -First 1
    }
    else {

        $selected = $files |
            Where-Object { $_ -notmatch "-nts-" } |
            Select-Object -First 1
    }

    if (-not $selected) {
        throw "Requested Thread Safety build was not found."
    }

    return [PSCustomObject]@{
        FileName = $selected
        Url      = "$OfficialReleaseUrl$selected"
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
            -UseBasicParsing

        $ProgressPreference = "Continue"

        if (-not (Test-Path $Destination)) {
            throw "Download completed but file was not found."
        }

        Write-OK "Download completed."
    }
    catch {

        throw "Download failed: $($_.Exception.Message)"
    }
}

# ============================================================
# INSTALL PHP
# ============================================================

function Install-Php {

    Write-Title "Install PHP"

    $requested = Read-Host `
        "Enter PHP version (example: 8.4 or exact 8.4.25)"

    if ([string]::IsNullOrWhiteSpace($requested)) {
        Write-Err "Version is required."
        return
    }

    if ($requested -notmatch "^\d+\.\d+(?:\.\d+)?$") {
        Write-Err "Invalid version format."
        Write-Info "Examples: 8.4   OR   8.4.25"
        return
    }

    # Architecture
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

    # Thread safety
    Write-Host ""
    Write-Host "Thread Safety:" -ForegroundColor Cyan
    Write-Host "  1. NTS - CLI / FastCGI (recommended for normal CLI use)"
    Write-Host "  2. TS  - Apache module / threaded SAPIs"

    $tsChoice = Read-Host "Choose [1/2] (default: 1)"

    if ([string]::IsNullOrWhiteSpace($tsChoice)) {
        $tsChoice = "1"
    }

    if ($tsChoice -eq "2") {
        $threadSafety = "ts"
    }
    else {
        $threadSafety = "nts"
    }

    # Installation path
    Write-Host ""

    $defaultPath = Join-Path $DefaultInstallRoot $requested

    $installPath = Read-Host `
        "Installation folder (default: $defaultPath)"

    if ([string]::IsNullOrWhiteSpace($installPath)) {
        $installPath = $defaultPath
    }

    $installPath = [Environment]::ExpandEnvironmentVariables($installPath)

    if (Test-Path $installPath) {

        $existingPhp = Join-Path $installPath "php.exe"

        if (Test-Path $existingPhp) {

            $existingVersion = Get-PhpVersionFromExecutable $existingPhp

            if ($existingVersion) {

                Write-Warn "PHP $existingVersion already exists here."

                $continue = Read-Host "Continue and overwrite/reinstall? [y/N]"

                if ($continue -notmatch "^[Yy]$") {
                    return
                }
            }
        }
    }

    # Find official release
    try {

        Write-Info "Looking for official PHP release..."

        $release = Find-PhpRelease `
            -RequestedVersion $requested `
            -ThreadSafety $threadSafety `
            -Architecture $architecture

        Write-OK "Found: $($release.FileName)"
        Write-Host ""
    }
    catch {

        Write-Err $_.Exception.Message
        return
    }

    # ZIP path
    $zipPath = Join-Path $DownloadDir $release.FileName

    # Download
    if (Test-Path $zipPath) {

        Write-Warn "ZIP already exists:"
        Write-Host $zipPath

        $useExisting = Read-Host "Use existing ZIP? [Y/n]"

        if ($useExisting -match "^[Nn]$") {
            Remove-Item $zipPath -Force
            Download-File $release.Url $zipPath
        }
    }
    else {
        Download-File $release.Url $zipPath
    }

    # Create temporary extraction directory
    $tempPath = Join-Path $ManagerRoot `
        ("temp-" + [guid]::NewGuid().ToString())

    try {

        New-Item -ItemType Directory `
            -Path $tempPath `
            -Force | Out-Null

        Write-Info "Extracting PHP..."

        Expand-Archive `
            -Path $zipPath `
            -DestinationPath $tempPath `
            -Force

        # Validate extracted PHP
        $tempPhp = Get-ChildItem `
            -Path $tempPath `
            -Filter "php.exe" `
            -File `
            -Recurse `
            -ErrorAction Stop |
            Select-Object -First 1

        if (-not $tempPhp) {
            throw "php.exe was not found after extraction."
        }

        $actualVersion = Get-PhpVersionFromExecutable `
            $tempPhp.FullName

        if (-not $actualVersion) {
            throw "Unable to execute extracted PHP."
        }

        Write-OK "Extracted PHP version: $actualVersion"

        if (-not (Test-VersionMatch `
                -Actual $actualVersion `
                -Requested $requested)) {

            throw @"
Version verification failed.

Requested : $requested
Downloaded: $actualVersion
"@
        }

        Write-OK "Version verification passed."

        # Create installation directory
        if (Test-Path $installPath) {

            Remove-Item `
                -Path $installPath `
                -Recurse `
                -Force
        }

        New-Item `
            -ItemType Directory `
            -Path $installPath `
            -Force | Out-Null

        Write-Info "Installing to:"
        Write-Host $installPath -ForegroundColor Gray

        # Move files
        Copy-Item `
            -Path (Join-Path $tempPhp.Directory.FullName "*") `
            -Destination $installPath `
            -Recurse `
            -Force

        $finalPhp = Join-Path $installPath "php.exe"

        if (-not (Test-Path $finalPhp)) {
            throw "Installation failed: php.exe missing."
        }

        $finalVersion = Get-PhpVersionFromExecutable $finalPhp

        if (-not $finalVersion) {
            throw "Installed PHP could not be executed."
        }

        Write-OK "Installed PHP $finalVersion"

        # Registry entry
        $registry = Get-Registry

        $newEntry = [PSCustomObject]@{
            version      = $finalVersion
            requested    = $requested
            path         = $finalPhp
            installPath  = $installPath
            architecture = $architecture
            threadSafety = $threadSafety
            installedAt  = (Get-Date).ToString("o")
        }

        $existing = @(
            $registry.installations |
            Where-Object {
                $_.path -ne $finalPhp
            }
        )

        $registry.installations = @(
            $existing + $newEntry
        )

        Save-Registry $registry

        # Create wrapper
        New-PhpWrapper `
            -PhpPath $finalPhp `
            -Version $finalVersion

        Write-OK "php$(Get-ShortVersion $finalVersion) command created."

        # Composer
        New-ComposerWrapper `
            -PhpPath $finalPhp `
            -Version $finalVersion

        # Delete ZIP?
        Write-Host ""

        $deleteZip = Read-Host `
            "Delete downloaded ZIP file? [Y/n]"

        if ($deleteZip -notmatch "^[Nn]$") {

            Remove-Item $zipPath -Force

            Write-OK "ZIP removed."
        }
        else {
            Write-Info "ZIP kept at:"
            Write-Host $zipPath
        }

        Write-Host ""
        Write-OK "PHP $finalVersion installation completed."

        Write-Host ""
        Write-Host "Command:" -ForegroundColor Cyan
        Write-Host "  php$(Get-ShortVersion $finalVersion) -v"

    }
    catch {

        Write-Err $_.Exception.Message
    }
    finally {

        if (Test-Path $tempPath) {
            Remove-Item `
                $tempPath `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# PHP WRAPPER
# ============================================================

function New-PhpWrapper {

    param(
        [string]$PhpPath,
        [string]$Version
    )

    $short = Get-ShortVersion $Version

    if (-not $short) {
        return
    }

    $wrapper = Join-Path `
        $WrapperRoot `
        "php$short.bat"

    $content = @"
@echo off
set "PHP_MANAGER_EXE=$PhpPath"
if not exist "%PHP_MANAGER_EXE%" (
    echo ERROR: PHP executable not found:
    echo %PHP_MANAGER_EXE%
    exit /b 1
)
"%PHP_MANAGER_EXE%" %*
"@

    Set-Content `
        -Path $wrapper `
        -Value $content `
        -Encoding ASCII

    Write-OK "Created $wrapper"
}

# ============================================================
# COMPOSER DISCOVERY
# ============================================================

function Find-Composer {

    $candidates = @(
        "C:\ProgramData\ComposerSetup\bin\composer.phar",
        "C:\ProgramData\ComposerSetup\bin\composer.bat",
        (Join-Path $env:APPDATA "Composer\composer.phar")
    )

    foreach ($candidate in $candidates) {

        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $command = Get-Command composer -ErrorAction SilentlyContinue

    if ($command) {
        return $command.Source
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

        Write-Warn "Composer was not found. cmp wrapper not created."
        return
    }

    $short = Get-ShortVersion $Version

    if (-not $short) {
        return
    }

    $wrapper = Join-Path `
        $WrapperRoot `
        "cmp$short.bat"

    if ($composer -match "\.phar$") {

        $content = @"
@echo off
set "PHP_MANAGER_EXE=$PhpPath"
set "COMPOSER_PHAR=$composer"

if not exist "%PHP_MANAGER_EXE%" (
    echo ERROR: PHP executable not found:
    echo %PHP_MANAGER_EXE%
    exit /b 1
)

if not exist "%COMPOSER_PHAR%" (
    echo ERROR: Composer PHAR not found:
    echo %COMPOSER_PHAR%
    exit /b 1
)

"%PHP_MANAGER_EXE%" "%COMPOSER_PHAR%" %*
"@
    }
    else {

        $content = @"
@echo off
set "PHP_MANAGER_EXE=$PhpPath"
set "COMPOSER_CMD=$composer"

if not exist "%PHP_MANAGER_EXE%" (
    echo ERROR: PHP executable not found:
    echo %PHP_MANAGER_EXE%
    exit /b 1
)

call "%COMPOSER_CMD%" %*
"@
    }

    Set-Content `
        -Path $wrapper `
        -Value $content `
        -Encoding ASCII

    Write-OK "Created cmp$short"
}

# ============================================================
# PATH MANAGEMENT
# ============================================================

function Get-PathEntries {
    param(
        [ValidateSet("User", "Machine")]
        [string]$Scope
    )

    $path = [Environment]::GetEnvironmentVariable(
        "Path",
        $Scope
    )

    if ([string]::IsNullOrWhiteSpace($path)) {
        return @()
    }

    return $path -split ";" |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }
}

function Add-ToPath {

    param(
        [ValidateSet("User", "Machine")]
        [string]$Scope
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
            $_.TrimEnd("\") -ieq $WrapperRoot.TrimEnd("\")
        }

    if ($already) {

        Write-Warn "$WrapperRoot is already in $Scope PATH."
        return
    }

    $newPath = (
        @($entries) + $WrapperRoot
    ) -join ";"

    try {

        [Environment]::SetEnvironmentVariable(
            "Path",
            $newPath,
            $Scope
        )

        Write-OK "Added $WrapperRoot to $Scope PATH."

        Write-Warn "Open a NEW terminal window for PATH changes to appear."
    }
    catch {

        Write-Err $_.Exception.Message

        if ($Scope -eq "Machine") {
            Write-Warn "Run PowerShell as Administrator for Machine PATH."
        }
    }
}

function Path-Menu {

    Write-Title "PATH Manager"

    Write-Host "1. Add to User PATH"
    Write-Host "2. Add to Machine PATH"
    Write-Host "3. Show User PATH status"
    Write-Host "4. Show Machine PATH status"
    Write-Host "5. Back"

    $choice = Read-Host "Select"

    switch ($choice) {

        "1" {
            Add-ToPath -Scope User
        }

        "2" {
            Add-ToPath -Scope Machine
        }

        "3" {
            $entries = Get-PathEntries -Scope User

            if ($entries -contains $WrapperRoot) {
                Write-OK "Wrapper directory exists in User PATH."
            }
            else {
                Write-Warn "Not present in User PATH."
            }
        }

        "4" {
            $entries = Get-PathEntries -Scope Machine

            if ($entries -contains $WrapperRoot) {
                Write-OK "Wrapper directory exists in Machine PATH."
            }
            else {
                Write-Warn "Not present in Machine PATH."
            }
        }
    }
}

# ============================================================
# VERIFY COMMANDS
# ============================================================

function Verify-VersionCommand {

    Write-Title "Verify PHP Command"

    $requested = Read-Host `
        "Enter command/version (example: php84 or 8.4)"

    if ([string]::IsNullOrWhiteSpace($requested)) {
        return
    }

    if ($requested -match "^php(\d+)$") {

        $short = $Matches[1]
        $commandName = "php$short"
    }
    elseif ($requested -match "^\d+\.\d+$") {

        $commandName = "php" + (
            $requested -replace "\.", ""
        )
    }
    else {

        $commandName = $requested
    }

    $cmd = Get-Command `
        $commandName `
        -ErrorAction SilentlyContinue

    if (-not $cmd) {

        Write-Err "$commandName was not found in PATH."
        Write-Info "Make sure $WrapperRoot is in PATH and open a new terminal."
        return
    }

    Write-Host ""
    Write-Host "Command:" -ForegroundColor Cyan
    Write-Host $cmd.Source

    $output = & $commandName -v 2>&1

    Write-Host ""
    Write-Host $output
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

    $choice = Read-Host "Select version number"

    if ($choice -notmatch "^\d+$") {
        return
    }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $versions.Count) {
        Write-Err "Invalid selection."
        return
    }

    $selected = $versions[$index]

    Write-Host ""
    Write-Host "Selected PHP $($selected.Version)" `
        -ForegroundColor Yellow

    $confirm = Read-Host "Really remove it? [y/N]"

    if ($confirm -notmatch "^[Yy]$") {
        return
    }

    $installPath = Split-Path `
        $selected.Path `
        -Parent

    try {

        Remove-Item `
            $installPath `
            -Recurse `
            -Force

        Write-OK "Removed $installPath"

        $registry = Get-Registry

        $registry.installations = @(
            $registry.installations |
            Where-Object {
                $_.path -ne $selected.Path
            }
        )

        Save-Registry $registry

        $short = Get-ShortVersion $selected.Version

        if ($short) {

            $phpWrapper = Join-Path `
                $WrapperRoot `
                "php$short.bat"

            $cmpWrapper = Join-Path `
                $WrapperRoot `
                "cmp$short.bat"

            if (Test-Path $phpWrapper) {
                Remove-Item $phpWrapper -Force
            }

            if (Test-Path $cmpWrapper) {
                Remove-Item $cmpWrapper -Force
            }
        }

        Write-OK "Registry and wrappers updated."
    }
    catch {

        Write-Err $_.Exception.Message
    }
}

# ============================================================
# REBUILD ALL WRAPPERS
# ============================================================

function Rebuild-Wrappers {

    Write-Title "Rebuilding PHP Wrappers"

    $versions = @(Find-PhpExecutables)

    if ($versions.Count -eq 0) {

        Write-Warn "No PHP installations found."
        return
    }

    foreach ($php in $versions) {

        $actual = Get-PhpVersionFromExecutable `
            $php.Path

        if (-not $actual) {
            Write-Warn "Could not verify $($php.Path)"
            continue
        }

        New-PhpWrapper `
            -PhpPath $php.Path `
            -Version $actual

        New-ComposerWrapper `
            -PhpPath $php.Path `
            -Version $actual
    }

    Write-OK "Wrappers rebuilt."
}

# ============================================================
# SYSTEM INFORMATION
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
    Write-Host "Manager root:"
    Write-Host "  $ManagerRoot"

    Write-Host ""
    Write-Host "Wrapper directory:"
    Write-Host "  $WrapperRoot"

    Write-Host ""
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {

    while ($true) {

        Write-Title "PHP Version Manager"

        Write-Host "Manager: $ManagerRoot" -ForegroundColor Gray
        Write-Host ""

        Write-Host "1. List installed PHP versions"
        Write-Host "2. Install / download PHP version"
        Write-Host "3. Remove PHP version"
        Write-Host "4. Verify phpXX command"
        Write-Host "5. Rebuild phpXX / cmpXX wrappers"
        Write-Host "6. PATH manager"
        Write-Host "7. System information"
        Write-Host "8. Exit"

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
                Remove-Php
            }

            "4" {
                Verify-VersionCommand
            }

            "5" {
                Rebuild-Wrappers
            }

            "6" {
                Path-Menu
            }

            "7" {
                Show-SystemInfo
            }

            "8" {
                Write-Host ""
                Write-Host "Goodbye." -ForegroundColor Cyan
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

Show-MainMenu
