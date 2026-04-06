# 1. Paths define karein
$phpSourceDir = "C:\wamp64\bin\php"
$scriptDestDir = "C:\scripts\php"
$composerPath = "C:\ProgramData\ComposerSetup\bin\composer.phar" # Check if this is correct

# 2. Destination folder banayein agar nahi hai to
if (!(Test-Path $scriptDestDir)) {
    New-Item -ItemType Directory -Path $scriptDestDir -Force
    Write-Host "✅ Created directory: $scriptDestDir" -ForegroundColor Green
}

# 3. WAMP ke PHP folders ko scan karein
$phpFolders = Get-ChildItem -Path $phpSourceDir -Directory -Filter "php*"

foreach ($folder in $phpFolders) {
    # Version nikalna (e.g., 8.5)
    $versionFull = $folder.Name.Replace("php", "") # e.g. 8.5.0
    $versionShort = $versionFull.Split('.')[0] + $versionFull.Split('.')[1] # e.g. 85

    $phpExe = Join-Path $folder.FullName "php.exe"
    
    if (Test-Path $phpExe) {
        # --- PHP Batch File (e.g. php85.bat) ---
        $phpBatFile = Join-Path $scriptDestDir "php$versionShort.bat"
        "@echo off`n`"$phpExe`" %*" | Out-File -FilePath $phpBatFile -Encoding ascii
        
        # --- Composer Batch File (e.g. comp85.bat) ---
        $compBatFile = Join-Path $scriptDestDir "comp$versionShort.bat"
        if (Test-Path $composerPath) {
            "@echo off`n`"$phpExe`" `"$composerPath`" %*" | Out-File -FilePath $compBatFile -Encoding ascii
        }

        Write-Host "🚀 Generated: php$versionShort.bat & comp$versionShort.bat for v$versionFull" -ForegroundColor Cyan
    }
}

Write-Host "`n🔥 All set! Now just add '$scriptDestDir' to your System PATH." -ForegroundColor Yellow
