#requires -Version 5.1
<#
PHP Version Manager for Windows
============================================================
Commands: php72, php80, php81, php82, php83, php84, php85
          cmp72, cmp80, cmp81, cmp82, cmp83, cmp84, cmp85
          php = active PHP, cmp = Composer using active PHP

IMPORTANT: Multiple physical installations of the same PHP major.minor
are grouped into ONE logical PHP version.

Example:
  C:\wamp64\bin\php\php7.2.34\php.exe
  C:\Users\Administrator\.php-manager\versions\7.2.34\php.exe

Both belong to: PHP 7.2

The manager selects one canonical installation and warns about
configuration/build differences instead of blindly merging them.

Run: .\generate-php-bat-files.ps1
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
# UI HELPERS
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
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    
    if (-not (Test-Path -LiteralPath $RegistryFile)) {
        @{
            installations = @()
            updatedAt = (Get-Date).ToString("o")
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
    }
    
    if (-not (Test-Path -LiteralPath $ActiveFile)) {
        @{
            activePath = $null
            activeVersion = $null
            updatedAt = (Get-Date).ToString("o")
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ActiveFile -Encoding UTF8
    }
}

# ============================================================
# REGISTRY OPERATIONS
# ============================================================
function Get-Registry {
    if (-not (Test-Path -LiteralPath $RegistryFile)) { Initialize-Manager }
    
    try {
        $raw = Get-Content -LiteralPath $RegistryFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [PSCustomObject]@{ 
                installations = @() 
                updatedAt = (Get-Date).ToString("o")
            }
        }
        
        $data = $raw | ConvertFrom-Json
        
        if ($null -eq $data.installations) {
            $data | Add-Member -NotePropertyName installations -NotePropertyValue @() -Force
        }
        
        if ($null -eq $data.updatedAt) {
            $data | Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date).ToString("o") -Force
        }
        
        return $data
    }
    catch {
        Write-Warn "Invalid registry. Recreating."
        $newRegistry = [PSCustomObject]@{
            installations = @()
            updatedAt = (Get-Date).ToString("o")
        }
        $newRegistry | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
        return $newRegistry
    }
}

function Save-Registry($Registry) {
    if ($null -eq $Registry.PSObject.Properties['installations']) {
        $Registry | Add-Member -NotePropertyName installations -NotePropertyValue @() -Force
    }
    if ($null -eq $Registry.PSObject.Properties['updatedAt']) {
        $Registry | Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date).ToString("o") -Force
    }
    
    $Registry | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $RegistryFile -Encoding UTF8
}

# ============================================================
# DUPLICATE MANAGEMENT - NEW FUNCTION
# ============================================================
function Resolve-DuplicatePhpVersions {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Versions,
        
        [Parameter(Mandatory = $true)]
        [object]$Registry
    )
    
    $duplicatesFound = $false
    $processedFamilies = @()
    
    foreach ($version in $Versions) {
        $family = $version.Family
        
        if ($processedFamilies -contains $family) {
            continue
        }
        $processedFamilies += $family
        
        $familyVersions = @($Versions | Where-Object { $_.Family -eq $family })
        
        if ($familyVersions.Count -le 1) {
            continue
        }
        
        $duplicatesFound = $true
        
        Write-Title "Duplicate PHP $family Found!"
        Write-Host "Found $($familyVersions.Count) installations for PHP $family" -ForegroundColor Yellow
        Write-Host ""
        
        for ($i = 0; $i -lt $familyVersions.Count; $i++) {
            $v = $familyVersions[$i]
            $marker = if ($v.Path -eq $version.Path) { " [CANONICAL]" } else { "" }
            Write-Host "[$($i + 1)] $($v.Version)$marker" -ForegroundColor Cyan
            Write-Host "    Path: $($v.Path)" -ForegroundColor Gray
            Write-Host "    Build: $($v.Architecture) / $($v.ThreadSafety)" -ForegroundColor Gray
            Write-Host "    Source: $($v.Source)" -ForegroundColor Gray
            Write-Host ""
        }
        
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  1. Keep only canonical version (recommended)" -ForegroundColor Gray
        Write-Host "  2. Select specific version to keep (remove others)" -ForegroundColor Gray
        Write-Host "  3. Move all versions to manager (keep all)" -ForegroundColor Gray
        Write-Host "  4. Skip (keep all as-is)" -ForegroundColor Gray
        
        $choice = Read-Host "Select option [1-4]"
        
        switch ($choice) {
            "1" {
                # Keep only canonical, remove others
                $canonical = $familyVersions | Sort-Object { Get-InstallationScore $_ $_.Source $null } -Descending | Select-Object -First 1
                
                Write-Host ""
                Write-Warn "Keeping canonical only: $($canonical.Path)"
                
                foreach ($v in $familyVersions) {
                    if ($v.Path -eq $canonical.Path) { continue }
                    
                    $confirm = Read-Host "Remove $($v.Path)? [y/N]"
                    if ($confirm -match "^[Yy]$") {
                        try {
                            Remove-Item -LiteralPath $v.InstallPath -Recurse -Force -ErrorAction SilentlyContinue
                            Write-OK "Removed: $($v.Path)"
                            
                            $Registry.installations = @($Registry.installations | Where-Object { $_.path -ine $v.Path })
                        }
                        catch {
                            Write-Err "Could not remove: $($_.Exception.Message)"
                        }
                    }
                }
            }
            
            "2" {
                $keepIndex = Read-Host "Enter number of version to keep [1-$($familyVersions.Count)]"
                if ($keepIndex -match "^\d+$") {
                    $idx = [int]$keepIndex - 1
                    if ($idx -ge 0 -and $idx -lt $familyVersions.Count) {
                        $keep = $familyVersions[$idx]
                        
                        Write-Host ""
                        Write-OK "Keeping: $($keep.Path)"
                        
                        foreach ($v in $familyVersions) {
                            if ($v.Path -eq $keep.Path) { continue }
                            
                            # Ask if want to move to manager directory
                            $moveToManager = Read-Host "Move $($v.Path) to manager? [y/N]"
                            if ($moveToManager -match "^[Yy]$") {
                                $newPath = Join-Path $VersionRoot $v.Version
                                try {
                                    if (Test-Path -LiteralPath $newPath) {
                                        Remove-Item -LiteralPath $newPath -Recurse -Force
                                    }
                                    Move-Item -LiteralPath $v.InstallPath -Destination $newPath -Force
                                    Write-OK "Moved to: $newPath"
                                    
                                    # Update registry with new path
                                    $Registry.installations = @($Registry.installations | Where-Object { $_.path -ine $v.Path })
                                    $Registry.installations += [PSCustomObject]@{
                                        version = $v.Version
                                        family = $v.Family
                                        path = Join-Path $newPath "php.exe"
                                        installPath = $newPath
                                        architecture = $v.Architecture
                                        threadSafety = $v.ThreadSafety
                                        iniPath = $v.IniPath
                                        extensionDir = $v.ExtensionDir
                                        extensionCount = $v.ExtensionCount
                                        registeredAt = (Get-Date).ToString("o")
                                    }
                                }
                                catch {
                                    Write-Err "Could not move: $($_.Exception.Message)"
                                }
                            }
                            else {
                                $confirm = Read-Host "Remove $($v.Path)? [y/N]"
                                if ($confirm -match "^[Yy]$") {
                                    try {
                                        Remove-Item -LiteralPath $v.InstallPath -Recurse -Force -ErrorAction SilentlyContinue
                                        Write-OK "Removed: $($v.Path)"
                                        $Registry.installations = @($Registry.installations | Where-Object { $_.path -ine $v.Path })
                                    }
                                    catch {
                                        Write-Err "Could not remove: $($_.Exception.Message)"
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            "3" {
                # Move all to manager
                Write-Host ""
                Write-Info "Moving all PHP $family versions to manager..."
                
                foreach ($v in $familyVersions) {
                    $newPath = Join-Path $VersionRoot $v.Version
                    if ($v.Path -like "$VersionRoot\*") { 
                        Write-Info "Already in manager: $($v.Path)"
                        continue 
                    }
                    
                    try {
                        if (Test-Path -LiteralPath $newPath) {
                            Remove-Item -LiteralPath $newPath -Recurse -Force
                        }
                        Move-Item -LiteralPath $v.InstallPath -Destination $newPath -Force
                        Write-OK "Moved to: $newPath"
                        
                        $Registry.installations = @($Registry.installations | Where-Object { $_.path -ine $v.Path })
                        $Registry.installations += [PSCustomObject]@{
                            version = $v.Version
                            family = $v.Family
                            path = Join-Path $newPath "php.exe"
                            installPath = $newPath
                            architecture = $v.Architecture
                            threadSafety = $v.ThreadSafety
                            iniPath = $v.IniPath
                            extensionDir = $v.ExtensionDir
                            extensionCount = $v.ExtensionCount
                            registeredAt = (Get-Date).ToString("o")
                        }
                    }
                    catch {
                        Write-Err "Could not move: $($_.Exception.Message)"
                    }
                }
            }
            
            "4" {
                Write-Info "Skipping duplicate resolution for PHP $family"
            }
            
            default {
                Write-Warn "Invalid option. Skipping..."
            }
        }
        
        Write-Host ""
    }
    
    if (-not $duplicatesFound) {
        Write-OK "No duplicate PHP versions found."
    }
    
    return $Registry
}

# ============================================================
# ACTIVE PHP OPERATIONS
# ============================================================
function Get-Active {
    if (-not (Test-Path -LiteralPath $ActiveFile)) {
        return [PSCustomObject]@{ activePath = $null; activeVersion = $null }
    }
    
    try {
        $raw = Get-Content -LiteralPath $ActiveFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [PSCustomObject]@{ activePath = $null; activeVersion = $null }
        }
        return $raw | ConvertFrom-Json
    }
    catch {
        return [PSCustomObject]@{ activePath = $null; activeVersion = $null }
    }
}

function Set-Active([string]$PhpPath, [string]$Version) {
    @{
        activePath = $PhpPath
        activeVersion = $Version
        updatedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ActiveFile -Encoding UTF8
    
    Write-OK "Active PHP: $Version"
}

# ============================================================
# VERSION HELPERS
# ============================================================
function Get-ShortVersion([string]$Version) {
    if ($Version -match "^(\d+)\.(\d+)") {
        return "$($Matches[1])$($Matches[2])"
    }
    return $null
}

function Get-VersionFamily([string]$Version) {
    if ($Version -match "^(\d+)\.(\d+)(?:\.\d+)?") {
        return "$($Matches[1]).$($Matches[2])"
    }
    return $null
}

function Test-VersionMatch([string]$Actual, [string]$Requested) {
    try {
        $v = [version]$Actual
        if ($Requested -match "^\d+\.\d+$") {
            $p = $Requested.Split(".")
            return ($v.Major -eq [int]$p[0] -and $v.Minor -eq [int]$p[1])
        }
        if ($Requested -match "^\d+\.\d+\.\d+$") {
            return $v -eq [version]$Requested
        }
    }
    catch {}
    return $false
}

function Get-PhpVersion([string]$PhpExe) {
    if (-not (Test-Path -LiteralPath $PhpExe -PathType Leaf)) { return $null }
    try {
        $v = & $PhpExe -r "echo PHP_VERSION;" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) {
            return ([string]$v).Trim()
        }
    }
    catch {}
    return $null
}

# ============================================================
# PHP PROFILE
# ============================================================
function New-PhpProfile([string]$PhpPath) {
    $profile = [PSCustomObject]@{
        Path             = $PhpPath
        Version          = $null
        MajorMinor       = $null
        Family           = $null
        Architecture     = "unknown"
        ThreadSafety     = "unknown"
        HasIni           = $false
        IniPath          = $null
        ExtensionDir     = $null
        LoadedExtensions = @()
        Extensions       = @()
        ExtensionCount   = 0
        IsUsable         = $false
    }

    if ([string]::IsNullOrWhiteSpace($PhpPath)) {
        return $profile
    }

    if (-not (Test-Path -LiteralPath $PhpPath -PathType Leaf)) {
        return $profile
    }

    $version = Get-PhpVersion $PhpPath

    if ([string]::IsNullOrWhiteSpace($version)) {
        return $profile
    }

    $profile.Version = $version
    $profile.Family = Get-VersionFamily $version

    if ($version -match "^(\d+\.\d+)") {
        $profile.MajorMinor = $Matches[1]
    }

    try {
        $versionOutput = @(& $PhpPath --version 2>$null)

        foreach ($line in $versionOutput) {
            $text = ([string]$line).Trim()

            if ($text -match "\bNTS\b") {
                $profile.ThreadSafety = "nts"
                break
            }

            if ($text -match "\bTS\b") {
                $profile.ThreadSafety = "ts"
                break
            }
        }

        $archOutput = & $PhpPath -r "echo PHP_INT_SIZE;" 2>$null

        if ($LASTEXITCODE -eq 0) {
            $archText = ([string]$archOutput).Trim()

            if ($archText -eq "8") {
                $profile.Architecture = "x64"
            }
            elseif ($archText -eq "4") {
                $profile.Architecture = "x86"
            }
        }

        $iniOutput = @(& $PhpPath --ini 2>$null)

        foreach ($line in $iniOutput) {
            $text = ([string]$line).Trim()

            if ($text -match "^Loaded Configuration File:\s*(.+)$") {
                $ini = $Matches[1].Trim()

                if (
                    $ini -and
                    $ini -notmatch "^\(none\)$" -and
                    (Test-Path -LiteralPath $ini -PathType Leaf)
                ) {
                    try {
                        $profile.IniPath = [IO.Path]::GetFullPath($ini)
                        $profile.HasIni = $true
                    }
                    catch {
                        $profile.IniPath = $ini
                        $profile.HasIni = $true
                    }
                }

                break
            }
        }

        if (-not $profile.HasIni) {
            $fallbackIni = Join-Path (Split-Path $PhpPath -Parent) "php.ini"

            if (Test-Path -LiteralPath $fallbackIni -PathType Leaf) {
                $profile.HasIni = $true
                $profile.IniPath = [IO.Path]::GetFullPath($fallbackIni)
            }
        }

        $extOutput = & $PhpPath -r "echo ini_get('extension_dir');" 2>$null

        if ($LASTEXITCODE -eq 0 -and $extOutput) {
            $extDir = ([string]$extOutput).Trim()

            if ($extDir) {
                if (-not [IO.Path]::IsPathRooted($extDir)) {
                    $extDir = Join-Path (Split-Path $PhpPath -Parent) $extDir
                }

                if (Test-Path -LiteralPath $extDir -PathType Container) {
                    $profile.ExtensionDir = [IO.Path]::GetFullPath($extDir)
                }
            }
        }

        $extOutput = & $PhpPath -r "echo implode('|', get_loaded_extensions());" 2>$null

        if ($LASTEXITCODE -eq 0 -and $extOutput) {
            $extensions = @(
                ([string]$extOutput) -split "\|" |
                ForEach-Object {
                    $_.Trim()
                } |
                Where-Object {
                    $_ -and $_ -notmatch '^[0-9]+$'
                } |
                Sort-Object -Unique
            )

            $profile.LoadedExtensions = @($extensions)
            $profile.Extensions = @($extensions)
            $profile.ExtensionCount = @($extensions).Count
        }

        $profile.IsUsable = $true
    }
    catch {
        # Keep partial information
    }

    return $profile
}

# ============================================================
# PHP DISCOVERY
# ============================================================
function Add-PhpResult($List, [string]$Path, [string]$Source) {
    if ($null -eq $List) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    try {
        $full = [IO.Path]::GetFullPath($Path)
    }
    catch {
        return
    }

    $exists = $false
    foreach ($existing in $List) {
        if ($null -ne $existing -and $existing.Path -ieq $full) {
            $exists = $true
            break
        }
    }
    
    if ($exists) {
        return
    }

    $profile = New-PhpProfile -PhpPath $full

    if ($null -eq $profile) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($profile.Version)) {
        return
    }

    $installPath = Split-Path $full -Parent

    $item = [PSCustomObject]@{
        Version          = $profile.Version
        Family           = $profile.Family
        MajorMinor       = $profile.MajorMinor
        Path             = $full
        InstallPath      = $installPath
        Source           = $Source
        Architecture     = $profile.Architecture
        ThreadSafety     = $profile.ThreadSafety
        HasIni           = [bool]$profile.HasIni
        IniPath          = $profile.IniPath
        ExtensionDir     = $profile.ExtensionDir
        LoadedExtensions = @($profile.LoadedExtensions)
        Extensions       = @($profile.Extensions)
        ExtensionCount   = [int]$profile.ExtensionCount
        IsUsable         = [bool]$profile.IsUsable
    }

    $List.Add($item) | Out-Null
}

function Find-PhpExecutables {
    $results = New-Object System.Collections.Generic.List[object]

    $registry = Get-Registry

    foreach ($item in @($registry.installations)) {
        if ($null -eq $item) {
            continue
        }

        $path = $item.path

        if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
            Add-PhpResult -List $results -Path ([string]$path) -Source "Registry"
        }
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

            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $roots += $p -split ";"
            }
        }
        catch {
        }
    }

    $normalizedRoots = New-Object System.Collections.Generic.List[string]

    foreach ($root in @($roots)) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) {
            continue
        }

        $root = [Environment]::ExpandEnvironmentVariables([string]$root).Trim()

        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }

        try {
            $fullRoot = [IO.Path]::GetFullPath($root)

            if (-not ($normalizedRoots -contains $fullRoot)) {
                $normalizedRoots.Add($fullRoot) | Out-Null
            }
        }
        catch {
        }
    }

    foreach ($root in @($normalizedRoots.ToArray())) {
        try {
            $files = Get-ChildItem -LiteralPath $root -Filter "php.exe" -File -Recurse -ErrorAction SilentlyContinue

            foreach ($file in @($files)) {
                Add-PhpResult -List $results -Path $file.FullName -Source "Scan"
            }
        }
        catch {
        }
    }

    $sorted = @(
        $results.ToArray() |
        Sort-Object `
            @{Expression = {
                try {
                    [version]$_.Version
                }
                catch {
                    [version]"0.0.0"
                }
            }; Descending = $true},
            @{Expression = { $_.Path }; Descending = $false}
    )

    return @($sorted)
}

# ============================================================
# PATH PRIORITY
# ============================================================
function Get-PathPriority([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return 999 }
    $full = $Path.TrimEnd('\').ToLowerInvariant()
    
    if ($full.StartsWith($VersionRoot.TrimEnd('\').ToLowerInvariant())) { return 10 }
    if ($full -match "\\wamp64?\\bin\\php\\") { return 20 }
    if ($full -match "\\xampp\\php") { return 30 }
    if ($full -match "^c:\\php") { return 40 }
    return 50
}

function Get-InstallationScore($Profile, [string]$Source, [string]$ActivePath) {
    $score = Get-PathPriority $Profile.Path
    
    if ($ActivePath -and $Profile.Path -ieq $ActivePath) { $score += 10000 }
    if ($Profile.Path -like "$VersionRoot\*") { $score += 500 }
    if ($Source -eq "Registry") { $score += 100 }
    if ($Profile.HasIni) { $score += 100 }
    if ($Profile.ExtensionDir) { $score += 50 }
    $score += [Math]::Min($Profile.ExtensionCount, 100)
    if ($env:PROCESSOR_ARCHITECTURE -eq "AMD64" -and $Profile.Architecture -eq "x64") { $score += 50 }
    if ($Profile.Path -like "$ManagerRoot\*") { $score += 50 }
    
    return $score
}

# ============================================================
# COMPARE AND SELECT
# ============================================================
function Compare-PhpInstallations($A, $B) {
    $differences = New-Object System.Collections.Generic.List[string]

    if ($null -eq $A -or $null -eq $B) {
        $differences.Add("invalid-profile") | Out-Null
        return @($differences.ToArray())
    }

    if ($A.Version -ne $B.Version) {
        $differences.Add("version") | Out-Null
    }

    if ($A.Architecture -ne $B.Architecture) {
        $differences.Add("architecture") | Out-Null
    }

    if ($A.ThreadSafety -ne $B.ThreadSafety) {
        $differences.Add("thread-safety") | Out-Null
    }

    if ($A.IniPath -ne $B.IniPath) {
        $differences.Add("php.ini") | Out-Null
    }

    if ($A.ExtensionDir -ne $B.ExtensionDir) {
        $differences.Add("extension-dir") | Out-Null
    }

    $extA = @($A.Extensions | Sort-Object)
    $extB = @($B.Extensions | Sort-Object)

    $jsonA = ConvertTo-Json $extA -Compress
    $jsonB = ConvertTo-Json $extB -Compress

    if ($jsonA -ne $jsonB) {
        $differences.Add("extensions") | Out-Null
    }

    return @($differences.ToArray())
}

function Select-CanonicalInstallation($Items) {
    $itemsArray = @(
        $Items |
        Where-Object {
            $null -ne $_ -and
            -not [string]::IsNullOrWhiteSpace([string]$_.Path)
        }
    )

    if ($itemsArray.Count -eq 0) {
        return $null
    }

    $active = Get-Active
    $activePath = $null

    if ($active) {
        $activePath = $active.activePath
    }

    $scored = @(
        foreach ($item in $itemsArray) {
            $score = Get-InstallationScore `
                $item `
                ([string]$item.Source) `
                ([string]$activePath)

            [PSCustomObject]@{
                Item  = $item
                Score = $score
            }
        }
    )

    $selected = $scored |
        Sort-Object `
            @{Expression = { $_.Score }; Descending = $true},
            @{Expression = {
                try {
                    [version]$_.Item.Version
                }
                catch {
                    [version]"0.0.0"
                }
            }; Descending = $true},
            @{Expression = { $_.Item.Path }; Descending = $false} |
        Select-Object -First 1

    if ($selected) {
        return $selected.Item
    }

    return $null
}

# ============================================================
# CANONICAL VERSIONS
# ============================================================
function Get-CanonicalPhpVersions {
    $all = @(Find-PhpExecutables)

    if ($all.Count -eq 0) {
        return @()
    }

    $groups = @(
        $all |
        Where-Object {
            $null -ne $_ -and
            -not [string]::IsNullOrWhiteSpace([string]$_.Family)
        } |
        Group-Object -Property Family
    )

    $canonical = New-Object System.Collections.Generic.List[object]

    foreach ($group in @($groups)) {
        $items = @(
            $group.Group |
            Where-Object {
                $null -ne $_
            }
        )

        if ($items.Count -eq 0) {
            continue
        }

        $selected = Select-CanonicalInstallation $items

        if ($null -eq $selected) {
            continue
        }

        $duplicates = @(
            $items |
            Where-Object {
                $_.Path -ine $selected.Path
            }
        )

        $conflicts = New-Object System.Collections.Generic.List[string]

        foreach ($duplicate in @($duplicates)) {
            $diff = @(Compare-PhpInstallations $selected $duplicate)

            if ($diff.Count -gt 0) {
                $conflicts.Add(
                    "$($duplicate.Path): $($diff -join ', ')"
                ) | Out-Null
            }
        }

        $canonicalItem = [PSCustomObject]@{
            Version          = $selected.Version
            Family           = $selected.Family
            MajorMinor       = $selected.MajorMinor
            Path             = $selected.Path
            InstallPath      = $selected.InstallPath
            Source           = $selected.Source
            Architecture     = $selected.Architecture
            ThreadSafety     = $selected.ThreadSafety
            HasIni           = [bool]$selected.HasIni
            IniPath          = $selected.IniPath
            ExtensionDir     = $selected.ExtensionDir
            Extensions       = @($selected.Extensions)
            LoadedExtensions = @($selected.LoadedExtensions)
            ExtensionCount   = [int]$selected.ExtensionCount
            DuplicateCount   = $duplicates.Count
            Duplicates       = @($duplicates)
            DuplicatePaths   = @(
                $duplicates |
                ForEach-Object {
                    $_.Path
                }
            )
            Conflicts         = @($conflicts.ToArray())
        }

        $canonical.Add($canonicalItem) | Out-Null
    }

    $sorted = @(
        $canonical.ToArray() |
        Sort-Object {
            try {
                [version]$_.Version
            }
            catch {
                [version]"0.0.0"
            }
        } -Descending
    )

    return @($sorted)
}

function Register-Php([string]$PhpPath, [string]$Version, [string]$Architecture = "unknown", [string]$ThreadSafety = "unknown", [string]$InstallPath) {
    $registry = Get-Registry
    $family = Get-VersionFamily $Version
    $ini = Get-PhpIniPath $PhpPath
    $extDir = Get-PhpExtensionDir $PhpPath
    $extensions = @(Get-PhpExtensions $PhpPath)
    
    $registry.installations = @($registry.installations | Where-Object { $_.path -ine $PhpPath })
    $registry.installations += [PSCustomObject]@{
        version = $Version
        family = $family
        path = $PhpPath
        installPath = $InstallPath
        architecture = $Architecture
        threadSafety = $ThreadSafety
        iniPath = $ini
        extensionDir = $extDir
        extensionCount = $extensions.Count
        registeredAt = (Get-Date).ToString("o")
    }
    $registry.updatedAt = (Get-Date).ToString("o")
    Save-Registry $registry
}

function Sync-Registry {
    $versions = @(Get-CanonicalPhpVersions)
    $registry = Get-Registry
    
    # Check for duplicates and resolve them
    $registry = Resolve-DuplicatePhpVersions -Versions $versions -Registry $registry
    
    $newItems = New-Object System.Collections.Generic.List[object]
    
    foreach ($php in $versions) {
        $existing = @($registry.installations | Where-Object { $_.path -ieq $php.Path }) | Select-Object -First 1
        $registeredAt = if ($existing -and $existing.registeredAt) { $existing.registeredAt } else { (Get-Date).ToString("o") }
        
        $newItems.Add([PSCustomObject]@{
            version = $php.Version
            family = $php.Family
            path = $php.Path
            installPath = $php.InstallPath
            architecture = $php.Architecture
            threadSafety = $php.ThreadSafety
            iniPath = $php.IniPath
            extensionDir = $php.ExtensionDir
            extensionCount = $php.ExtensionCount
            registeredAt = $registeredAt
        }) | Out-Null
    }
    
    $registry.installations = $newItems.ToArray()
    $registry.updatedAt = (Get-Date).ToString("o")
    
    Save-Registry $registry
    return $versions
}

# ============================================================
# LEGACY FUNCTIONS
# ============================================================
function Get-PhpArchitecture([string]$PhpExe) {
    $profile = New-PhpProfile $PhpExe
    return $profile.Architecture
}

function Get-PhpThreadSafety([string]$PhpExe) {
    $profile = New-PhpProfile $PhpExe
    return $profile.ThreadSafety
}

function Get-PhpIniPath([string]$PhpExe) {
    $profile = New-PhpProfile $PhpExe
    return $profile.IniPath
}

function Get-PhpExtensionDir([string]$PhpExe) {
    $profile = New-PhpProfile $PhpExe
    return $profile.ExtensionDir
}

function Get-PhpExtensions([string]$PhpExe) {
    $profile = New-PhpProfile $PhpExe
    return $profile.Extensions
}

# ============================================================
# BATCH ESCAPING
# ============================================================
function Escape-BatchPath([string]$Path) {
    if ($null -eq $Path) { return "" }
    return $Path.Replace("%", "%%")
}

# ============================================================
# WRAPPER GENERATION
# ============================================================
function New-PhpWrapper([string]$PhpPath, [string]$Version) {
    $short = Get-ShortVersion $Version
    if (-not $short) { return }
    
    $wrapper = Join-Path $WrapperRoot "php$short.bat"
    $safePath = Escape-BatchPath $PhpPath
    
    $content = "@echo off`r`nsetlocal`r`nset `"PHP_EXE=$safePath`"`r`nif not exist `"%PHP_EXE%`" (`r`n    echo ERROR: PHP $Version not found.`r`n    echo %PHP_EXE%`r`n    exit /b 1`r`n)`r`n`"%PHP_EXE%`" %*`r`nset `"EXITCODE=%ERRORLEVEL%`"`r`nendlocal & exit /b %EXITCODE%`r`n"
    
    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created php$short.bat -> $PhpPath"
}

function Find-Composer {
    $candidates = @(
        "C:\ProgramData\ComposerSetup\bin\composer.phar",
        (Join-Path $env:APPDATA "Composer\composer.phar"),
        (Join-Path $env:LOCALAPPDATA "Composer\composer.phar")
    )
    
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return [PSCustomObject]@{ Type = "phar"; Path = $path }
        }
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
            }
            catch {}
        }
        return [PSCustomObject]@{ Type = "command"; Path = $source }
    }
    return $null
}

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
        
        $content = "@echo off`r`nsetlocal`r`nset `"PHP_EXE=$safePhp`"`r`nset `"COMPOSER_PHAR=$safePhar`"`r`nif not exist `"%PHP_EXE%`" (`r`n    echo ERROR: PHP $Version not found.`r`n    echo %PHP_EXE%`r`n    exit /b 1`r`n)`r`nif not exist `"%COMPOSER_PHAR%`" (`r`n    echo ERROR: Composer PHAR not found.`r`n    echo %COMPOSER_PHAR%`r`n    exit /b 1`r`n)`r`n`"%PHP_EXE%`" `"%COMPOSER_PHAR%`" %*`r`nset `"EXITCODE=%ERRORLEVEL%`"`r`nendlocal & exit /b %EXITCODE%`r`n"
    }
    else {
        Write-Warn "Composer was found as command rather than PHAR. cmp$short will use composer.bat."
        $safePhp = Escape-BatchPath $PhpPath
        $safeCmd = Escape-BatchPath $composer.Path
        
        $content = "@echo off`r`nsetlocal`r`nset `"PHP_EXE=$safePhp`"`r`nset `"COMPOSER_CMD=$safeCmd`"`r`nif not exist `"%PHP_EXE%`" (`r`n    echo ERROR: PHP $Version not found.`r`n    exit /b 1`r`n)`r`ncall `"%COMPOSER_CMD%`" %*`r`nset `"EXITCODE=%ERRORLEVEL%`"`r`nendlocal & exit /b %EXITCODE%`r`n"
    }
    
    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created cmp$short.bat -> PHP $Version"
}

function New-ActivePhpHelper {
    $helper = Join-Path $WrapperRoot "get-active-php.ps1"
    $escapedActiveFile = $ActiveFile.Replace("'", "''")
    
    $content = "`$ErrorActionPreference = `"SilentlyContinue`"`r`n`$file = '$escapedActiveFile'`r`nif (Test-Path -LiteralPath `$file) {`r`n    try {`r`n        `$j = Get-Content -LiteralPath `$file -Raw | ConvertFrom-Json`r`n        if (`$j.activePath) { Write-Output `$j.activePath }`r`n    } catch {}`r`n}"
    
    Set-Content -LiteralPath $helper -Value $content -Encoding UTF8
}

function New-ActivePhpWrapper {
    $wrapper = Join-Path $WrapperRoot "php.bat"
    
    $content = "@echo off`r`nsetlocal`r`nset `"ACTIVE_FILE=$([string](Escape-BatchPath $ActiveFile))`"`r`nif not exist `"%ACTIVE_FILE%`" (`r`n    echo ERROR: Active PHP configuration not found.`r`n    exit /b 1`r`n)`r`nfor /f `"usebackq delims=`" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0get-active-php.ps1`"`) do set `"PHP_EXE=%%A`"`r`nif not defined PHP_EXE (`r`n    echo ERROR: No active PHP selected.`r`n    exit /b 1`r`n)`r`nif not exist `"%PHP_EXE%`" (`r`n    echo ERROR: Active PHP executable not found.`r`n    echo %PHP_EXE%`r`n    exit /b 1`r`n)`r`n`"%PHP_EXE%`" %*`r`nset `"EXITCODE=%ERRORLEVEL%`"`r`nendlocal & exit /b %EXITCODE%`r`n"
    
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
        
        $content = "@echo off`r`nsetlocal`r`nfor /f `"usebackq delims=`" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0get-active-php.ps1`"`) do set `"PHP_EXE=%%A`"`r`nif not defined PHP_EXE (`r`n    echo ERROR: No active PHP selected.`r`n    exit /b 1`r`n)`r`nif not exist `"%PHP_EXE%`" (`r`n    echo ERROR: Active PHP not found.`r`n    echo %PHP_EXE%`r`n    exit /b 1`r`n)`r`nset `"COMPOSER_PHAR=$safePhar`"`r`nif not exist `"%COMPOSER_PHAR%`" (`r`n    echo ERROR: Composer PHAR not found.`r`n    exit /b 1`r`n)`r`n`"%PHP_EXE%`" `"%COMPOSER_PHAR%`" %*`r`nset `"EXITCODE=%ERRORLEVEL%`"`r`nendlocal & exit /b %EXITCODE%`r`n"
    }
    else {
        $safeCmd = Escape-BatchPath $composer.Path
        
        $content = "@echo off`r`nsetlocal`r`nfor /f `"usebackq delims=`" %%A in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0get-active-php.ps1`"`) do set `"PHP_EXE=%%A`"`r`nif not defined PHP_EXE (`r`n    echo ERROR: No active PHP selected.`r`n    exit /b 1`r`n)`r`nif not exist `"%PHP_EXE%`" (`r`n    echo ERROR: Active PHP not found.`r`n    exit /b 1`r`n)`r`nset `"COMPOSER_CMD=$safeCmd`"`r`ncall `"%COMPOSER_CMD%`" %*`r`nset `"EXITCODE=%ERRORLEVEL%`"`r`nendlocal & exit /b %EXITCODE%`r`n"
    }
    
    Set-Content -LiteralPath $wrapper -Value $content -Encoding ASCII
    Write-OK "Created active cmp command"
}

# ============================================================
# PATH MANAGEMENT
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
    
    $versions = @(Get-CanonicalPhpVersions)
    if ($versions.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }
    
    Sync-Registry | Out-Null
    
    # Remove stale version wrappers
    $validShortVersions = @($versions | ForEach-Object { Get-ShortVersion $_.Version })
    
    foreach ($file in @(Get-ChildItem -LiteralPath $WrapperRoot -Filter "php*.bat" -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -eq "php.bat") { continue }
        if ($file.BaseName -match "^php(\d+)$") {
            if ($validShortVersions -notcontains $Matches[1]) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                Write-Info "Removed stale wrapper: $($file.Name)"
            }
        }
    }
    
    foreach ($file in @(Get-ChildItem -LiteralPath $WrapperRoot -Filter "cmp*.bat" -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -eq "cmp.bat") { continue }
        if ($file.BaseName -match "^cmp(\d+)$") {
            if ($validShortVersions -notcontains $Matches[1]) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                Write-Info "Removed stale wrapper: $($file.Name)"
            }
        }
    }
    
    # Build wrappers
    foreach ($php in $versions) {
        $actual = Get-PhpVersion $php.Path
        if (-not $actual) { continue }
        
        Register-Php -PhpPath $php.Path -Version $actual -Architecture $php.Architecture -ThreadSafety $php.ThreadSafety -InstallPath $php.InstallPath
        New-PhpWrapper -PhpPath $php.Path -Version $actual
        New-ComposerWrapper -PhpPath $php.Path -Version $actual
    }
    
    New-ActivePhpHelper
    New-ActivePhpWrapper
    New-ActiveComposerWrapper
    Add-ManagerToUserPath
    
    # Duplicate warnings
    foreach ($php in $versions) {
        if ($php.DuplicateCount -gt 0) {
            Write-Warn "PHP $($php.Family) has $($php.DuplicateCount) duplicate installation(s)."
            Write-Host "  Canonical:"; Write-Host "    $($php.Path)" -ForegroundColor Gray
            foreach ($dup in $php.Duplicates) {
                Write-Host "  Duplicate:"; Write-Host "    $($dup.Path)" -ForegroundColor DarkGray
            }
            if ($php.Conflicts.Count -gt 0) {
                Write-Warn "Configuration/build differences detected for PHP $($php.Family):"
                foreach ($conflict in $php.Conflicts) {
                    Write-Host "    $conflict" -ForegroundColor Yellow
                }
                Write-Info "Extensions were NOT merged automatically because PHP DLLs/configuration must stay build-compatible."
            }
        }
    }
    
    Write-OK "All wrappers rebuilt."
}

# ============================================================
# COMMANDS
# ============================================================
function Show-InstalledVersions {
    Write-Title "Installed PHP Versions"
    
    $versions = @(Get-CanonicalPhpVersions)
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
        Write-Host "         Build      : $($php.Architecture) / $($php.ThreadSafety)" -ForegroundColor DarkGray
        Write-Host "         php.ini    : $(if ($php.HasIni) { $php.IniPath } else { '(none)' })" -ForegroundColor DarkGray
        Write-Host "         Extensions : $($php.ExtensionCount)" -ForegroundColor DarkGray
        
        if ($php.DuplicateCount -gt 0) {
            Write-Host "         [INFO] $($php.DuplicateCount) duplicate installation(s) detected." -ForegroundColor Yellow
            foreach ($duplicate in @($php.DuplicatePaths)) {
                Write-Host "                 duplicate: $duplicate" -ForegroundColor DarkYellow
            }
        }
        Write-Host ""
    }
}

function Switch-ActivePhp {
    Write-Title "Switch Active PHP"
    
    $versions = @(Get-CanonicalPhpVersions)
    if ($versions.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }
    
    for ($i = 0; $i -lt $versions.Count; $i++) {
        $php = $versions[$i]
        Write-Host ""
        Write-Host "[$($i + 1)] PHP $($php.Version)" -ForegroundColor Cyan
        Write-Host "    Family: $($php.Family)" -ForegroundColor Gray
        Write-Host "    Path:   $($php.Path)" -ForegroundColor Gray
        Write-Host "    Build:  $($php.Architecture) / $($php.ThreadSafety)" -ForegroundColor Gray
        if ($php.Conflicts.Count -gt 0) {
            Write-Host "    WARNING: duplicate configuration differences detected" -ForegroundColor Yellow
        }
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

function Show-ActivePhp {
    Write-Title "Active PHP"

    $active = Get-Active

    if (-not $active.activePath) {
        Write-Warn "No active PHP selected."
        return
    }

    Write-Host "Version : $($active.activeVersion)" -ForegroundColor Cyan
    Write-Host "Path    : $($active.activePath)" -ForegroundColor Gray

    if (-not (Test-Path -LiteralPath $active.activePath -PathType Leaf)) {
        Write-Err "Active PHP executable does not exist."
        return
    }

    $profile = New-PhpProfile $active.activePath

    if ($profile -and $profile.IsUsable) {
        Write-OK "Executable reports PHP $($profile.Version)"
        Write-Host "Build   : $($profile.Architecture) / $($profile.ThreadSafety)"
        Write-Host "Ini     : $(if ($profile.HasIni) { $profile.IniPath } else { '(none)' })"
        Write-Host "Ext dir : $(if ($profile.ExtensionDir) { $profile.ExtensionDir } else { '(none)' })"
        Write-Host "Ext     : $($profile.ExtensionCount)"
    }
    else {
        Write-Err "PHP executable could not be profiled."
    }
}

function Remove-Php {
    Write-Title "Remove PHP"
    
    $versions = @(Get-CanonicalPhpVersions)
    if ($versions.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }
    
    for ($i = 0; $i -lt $versions.Count; $i++) {
        $php = $versions[$i]
        Write-Host ""
        Write-Host "[$($i + 1)] PHP $($php.Version)" -ForegroundColor Cyan
        Write-Host "    Path: $($php.Path)" -ForegroundColor Gray
        if ($php.DuplicateCount -gt 0) {
            Write-Host "    Duplicate installations: $($php.DuplicateCount)" -ForegroundColor Yellow
            foreach ($dup in $php.Duplicates) {
                Write-Host "      $($dup.Path)" -ForegroundColor DarkGray
            }
        }
    }
    
    $choice = Read-Host "Select PHP version"
    if ($choice -notmatch "^\d+$") { return }
    
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $versions.Count) {
        Write-Err "Invalid selection."
        return
    }
    
    $selected = $versions[$index]
    $active = Get-Active
    
    if ($active.activePath -and $selected.Path -ieq $active.activePath) {
        Write-Warn "This PHP is active. Switch active PHP first."
        return
    }
    
    Write-Host ""
    Write-Host "Canonical PHP:"
    Write-Host "  $($selected.Version)"
    Write-Host "  $($selected.Path)"
    
    $confirm = Read-Host "Really remove canonical PHP installation? [y/N]"
    if ($confirm -notmatch "^[Yy]$") { return }
    
    $installPath = $selected.InstallPath
    
    try {
        Remove-Item -LiteralPath $installPath -Recurse -Force
        Write-OK "Removed: $installPath"
    }
    catch {
        Write-Err "Could not remove installation: $($_.Exception.Message)"
        return
    }
    
    $registry = Get-Registry
    $registry.installations = @($registry.installations | Where-Object { $_.path -ine $selected.Path })
    $registry.updatedAt = (Get-Date).ToString("o")
    Save-Registry $registry
    
    $short = Get-ShortVersion $selected.Version
    foreach ($name in @("php$short.bat", "cmp$short.bat")) {
        $file = Join-Path $WrapperRoot $name
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-OK "PHP $($selected.Version) removed."
    Rebuild-Wrappers
}

function Verify-Commands {
    Write-Title "Verify Commands"
    
    $versions = @(Get-CanonicalPhpVersions)
    foreach ($php in $versions) {
        $short = Get-ShortVersion $php.Version
        Verify-Wrapper "php$short" $php.Path $php.Version | Out-Null
        Verify-Wrapper "cmp$short" $php.Path $php.Version | Out-Null
        
        if ($php.DuplicateCount -gt 0) {
            Write-Warn "PHP $($php.Family): $($php.DuplicateCount) duplicate installation(s) detected."
            if ($php.Conflicts.Count -gt 0) {
                Write-Warn "Differences:"
                $php.Conflicts | ForEach-Object { Write-Host "  $_" }
            }
        }
    }
    
    $active = Get-Active
    if ($active.activePath) {
        Verify-Wrapper "php" $active.activePath $active.activeVersion | Out-Null
        Write-OK "Active mapping: php -> $($active.activeVersion)"
        Write-OK "Active mapping: cmp -> $($active.activeVersion)"
    }
}

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
# DIAGNOSTICS
# ============================================================
function Show-DuplicateDiagnostics {
    Write-Title "PHP Duplicate / Configuration Diagnostics"
    
    $all = @(Find-PhpExecutables)
    if ($all.Count -eq 0) {
        Write-Warn "No PHP installations found."
        return
    }
    
    $groups = @($all | Group-Object Family)
    
    foreach ($group in $groups) {
        $items = @($group.Group)
        Write-Host ""
        Write-Host "PHP $($group.Name)" -ForegroundColor Cyan
        Write-Host "----------------------------------------"
        
        if ($items.Count -eq 1) {
            Write-OK "Only one installation found."
            $item = $items[0]
            Write-Host "Path         : $($item.Path)"
            Write-Host "Version      : $($item.Version)"
            Write-Host "Architecture : $($item.Architecture)"
            Write-Host "Thread Safety: $($item.ThreadSafety)"
            Write-Host "php.ini      : $($item.IniPath)"
            Write-Host "Extension dir: $($item.ExtensionDir)"
            Write-Host "Extensions   : $($item.ExtensionCount)"
            continue
        }
        
        Write-Warn "$($items.Count) physical installations found for PHP $($group.Name)."
        $canonical = Select-CanonicalInstallation $items
        
        Write-Host ""
        Write-Host "CANONICAL INSTALLATION:" -ForegroundColor Green
        Write-Host "  $($canonical.Path)" -ForegroundColor Green
        
        foreach ($item in $items) {
            Write-Host ""
            Write-Host "Installation:" -ForegroundColor Yellow
            Write-Host "  Path         : $($item.Path)"
            Write-Host "  Version      : $($item.Version)"
            Write-Host "  Architecture : $($item.Architecture)"
            Write-Host "  Thread Safety: $($item.ThreadSafety)"
            Write-Host "  php.ini      : $($item.IniPath)"
            Write-Host "  Extension dir: $($item.ExtensionDir)"
            Write-Host "  Extensions   : $($item.ExtensionCount)"
            
            if ($item.Path -ieq $canonical.Path) {
                Write-Host "  ROLE         : CANONICAL" -ForegroundColor Green
            } else {
                $diff = @(Compare-PhpInstallations $canonical $item)
                if ($diff.Count -eq 0) {
                    Write-Host "  DIFFERENCES  : none" -ForegroundColor Gray
                } else {
                    Write-Host "  DIFFERENCES  : $($diff -join ', ')" -ForegroundColor Red
                }
            }
        }
    }
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
        Write-Host "10. Duplicate / configuration diagnostics"
        Write-Host "11. Exit"
        
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
            "10" { Show-DuplicateDiagnostics }
            "11" { return }
            default { Write-Warn "Invalid option." }
        }
        
        Write-Host ""
        Read-Host "Press ENTER to continue" | Out-Null
    }
}

function Path-Menu {
    Write-Title "PATH Manager"
    Write-Host "1. Add Manager to User PATH"
    Write-Host "2. Refresh current PowerShell PATH"
    Write-Host "3. Show wrapper directory"
    Write-Host "4. Find phpXX/cmpXX conflicts"
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
            $commands = @(
                "php72", "php80", "php81", "php82", "php83", "php84", "php85",
                "cmp72", "cmp80", "cmp81", "cmp82", "cmp83", "cmp84", "cmp85",
                "php", "cmp"
            )
            foreach ($cmd in $commands) {
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
# INSTALL FUNCTION
# ============================================================
function Install-Php {
    Write-Title "Install PHP"
    
    $requested = Read-Host "PHP version (7.2 / 7.2.34 / 8.5 / 8.5.0)"
    if ($requested -notmatch "^\d+\.\d+(?:\.\d+)?$") { Write-Err "Invalid version."; return }
    
    $existingFamily = Get-VersionFamily $requested
    $existingVersions = @(Get-CanonicalPhpVersions | Where-Object { $_.Family -eq $existingFamily })
    
    if ($existingVersions.Count -gt 0) {
        Write-Warn "PHP $existingFamily is already installed."
        foreach ($existing in $existingVersions) {
            Write-Host "  Version : $($existing.Version)"
            Write-Host "  Path    : $($existing.Path)"
            Write-Host "  Build   : $($existing.Architecture) / $($existing.ThreadSafety)"
        }
        $continue = Read-Host "Continue and install another build for PHP $existingFamily? [y/N]"
        if ($continue -notmatch "^[Yy]$") { Write-Warn "Installation cancelled."; return }
    }
    
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
        Write-Host "File  : $($release.FileName)"
        Write-Host "Source: $($release.Source)"
        Write-Host "Build : $($release.Architecture) / $($release.ThreadSafety)"
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
                    $existingIni = Join-Path $installPath "php.ini"
                    if (Test-Path -LiteralPath $existingIni) {
                        Write-Info "Existing php.ini detected. It will be backed up."
                        $backup = "$existingIni.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                        Copy-Item -LiteralPath $existingIni -Destination $backup -Force
                    }
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
            Rebuild-Wrappers
            
            $makeActive = Read-Host "Make PHP $finalVersion active? [Y/n]"
            if ($makeActive -notmatch "^[Nn]$") {
                Set-Active -PhpPath $finalPhp -Version $finalVersion
                New-ActivePhpHelper
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
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  php$((Get-ShortVersion $finalVersion)) -v"
            Write-Host "  cmp$((Get-ShortVersion $finalVersion)) --version"
            Write-Host "  php -v"
            Write-Host "  cmp --version"
        }
        finally {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Err $_.Exception.Message
    }
}

# ============================================================
# WEB HELPERS
# ============================================================
function Get-WebText([string]$Url) {
    Write-Info "Fetching $Url"
    $ProgressPreference = "SilentlyContinue"
    try { return (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60).Content }
    finally { $ProgressPreference = "Continue" }
}

function Get-ReleaseFiles([string]$Html) {
    $pattern = 'php-\d+\.\d+\.\d+-(?:nts-)?Win32-[^"\s<>]+-(?:x64|x86)\.zip'
    return @([regex]::Matches($Html, $pattern, "IgnoreCase") | ForEach-Object { $_.Value } | Sort-Object -Unique)
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
    $current = $null; $archive = $null
    try { $current = Get-WebText $ReleaseUrl } catch { Write-Warn "Current releases unavailable." }
    try { $archive = Get-WebText $ArchiveUrl } catch { Write-Warn "Archive releases unavailable." }
    
    $files = @()
    if ($current) { $files += Get-ReleaseFiles $current }
    if ($archive) { $files += Get-ReleaseFiles $archive }
    $files = @($files | Sort-Object -Unique)
    
    $parsed = @($files | ForEach-Object { $x = Parse-PhpZip $_; if ($x -and $x.Architecture -eq $Architecture -and $x.ThreadSafety -eq $ThreadSafety) { $x } })
    
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

function Download-File([string]$Url, [string]$Destination) {
    Write-Info "Downloading $Url"
    $ProgressPreference = "SilentlyContinue"
    try { Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 600 }
    finally { $ProgressPreference = "Continue" }
    if (-not (Test-Path -LiteralPath $Destination)) { throw "Download failed." }
    if ((Get-Item -LiteralPath $Destination).Length -lt 10000) { throw "Downloaded ZIP is invalid or incomplete." }
    Write-OK "Download completed."
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