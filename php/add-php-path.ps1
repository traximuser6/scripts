# add-path.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       Add Folder to Windows PATH       " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# User se folder path lena
$folderPath = Read-Host "Enter the folder path to add to PATH"

# Example
# C:\scripts\php

# Check folder exist karta hai ya nahi
if (-not (Test-Path $folderPath -PathType Container)) {
    Write-Host ""
    Write-Host "ERROR: Folder does not exist!" -ForegroundColor Red
    Write-Host "You entered: $folderPath"
    exit
}

# Current Machine PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")

# Check agar already PATH mein hai
$pathEntries = $currentPath -split ";"

if ($pathEntries -contains $folderPath) {
    Write-Host ""
    Write-Host "This folder is already in Machine PATH." -ForegroundColor Yellow
}
else {
    # PATH mein folder add karna
    $newPath = $currentPath.TrimEnd(";") + ";" + $folderPath

    [Environment]::SetEnvironmentVariable(
        "Path",
        $newPath,
        "Machine"
    )

    Write-Host ""
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "$folderPath has been added to Machine PATH."
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan