# 1. Paths define karein
$phpSourceDir = "C:\wamp64\bin\php"
$scriptDestDir = "C:\scripts\php"
# Composer path verify karlein (usually yahan hota hai)
$composerPath = "C:\ProgramData\ComposerSetup\bin\composer.phar" 

# 2. Destination folder banayein agar nahi hai to
if (!(Test-Path $scriptDestDir)) {
    New-Item -ItemType Directory -Path $scriptDestDir -Force
    Write-Host "✅ Created directory: $scriptDestDir" -ForegroundColor Green
}

# 3. WAMP ke PHP folders ko scan karein
$phpFolders = Get-ChildItem -Path $phpSourceDir -Directory -Filter "php*"

foreach ($folder in $phpFolders) {
    # Version nikalna (e.g., 8.2.29 -> 82)
    $versionParts = $folder.Name.Replace("php", "").Split('.')
    if ($versionParts.Count -ge 2) {
        $versionShort = $versionParts[0] + $versionParts[1] # e.g. 82
        $versionFull = $folder.Name.Replace("php", "")
        
        $phpExe = Join-Path $folder.FullName "php.exe"
        
        if (Test-Path $phpExe) {
            # --- PHP Batch File (e.g. php82.bat) ---
            $phpBatFile = Join-Path $scriptDestDir "php$versionShort.bat"
            "@echo off`n`"$phpExe`" %*" | Out-File -FilePath $phpBatFile -Encoding ascii
            
            # --- Composer Batch File (Ab yeh cmp82.bat banay ga) ---
            $compBatFile = Join-Path $scriptDestDir "cmp$versionShort.bat"
            if (Test-Path $composerPath) {
                "@echo off`n`"$phpExe`" `"$composerPath`" %*" | Out-File -FilePath $compBatFile -Encoding ascii
            }

            Write-Host "🚀 Generated: php$versionShort.bat & cmp$versionShort.bat for v$versionFull" -ForegroundColor Cyan
        }
    }
}

Write-Host "`n🔥 All set! 'cmp' prefix applied." -ForegroundColor Yellow
Write-Host "👉 Ab 'C:\scripts\php' ko System PATH mein add kar ke terminal restart karein." -ForegroundColor White
