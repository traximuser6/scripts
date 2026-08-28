# 📁 Scripts Collection for Windows Development

## Overview

This repository contains a collection of useful PowerShell and batch scripts for Windows development environments. These scripts help manage PHP versions, system paths, and development tools.

## 📂 Project Structure

```
C:\projects\scripts\
├── boot-up-apps.bat          # Windows boot-up applications manager
├── readme.md                  # This documentation
└── php\                       # PHP management scripts
    ├── add-php-path.ps1       # Add PHP to system PATH
    ├── generate-php-bat-files.ps1  # PHP Version Manager
    └── info.md                # PHP scripts documentation
```

---

## 🚀 General System Scripts

### `boot-up-apps.bat`

**Purpose**: Manages applications that start automatically with Windows boot.

**Features**:
- Lists all startup applications
- Enables/disables startup items
- Adds/removes applications from startup
- Shows startup folder location

**Usage**:

```batch
# Run as Administrator
boot-up-apps.bat

# Commands within the script:
1. List startup applications
2. Enable a startup application
3. Disable a startup application
4. Add application to startup
5. Remove application from startup
6. Open startup folder
7. Exit
```

---

## 🐘 PHP Management Scripts

### `php/generate-php-bat-files.ps1`

**Purpose**: Complete PHP Version Manager for Windows. Discovers all PHP installations and creates convenient batch wrappers.

**Features**:
- Auto-discovers PHP from WAMP, XAMPP, custom paths, and PATH
- Creates batch files for each PHP version (`php72.bat`, `php80.bat`, etc.)
- Creates Composer wrappers for each PHP version (`cmp72.bat`, etc.)
- Manages active PHP version
- Handles duplicate installations
- Downloads and installs new PHP versions from official sources

**Usage**:

```powershell
# Run as Administrator
.\php\generate-php-bat-files.ps1

# Interactive Menu:
1. List installed PHP versions
2. Install / download PHP
3. Switch active PHP
4. Show active PHP
5. Remove PHP
6. Verify phpXX / cmpXX / php / cmp
7. Rebuild wrappers
8. PATH manager
9. System information
10. Duplicate / configuration diagnostics
11. Exit
```

**Available Commands After Installation**:

```bash
# PHP Commands
php72 -v          # PHP 7.2
php80 -v          # PHP 8.0
php81 -v          # PHP 8.1
php82 -v          # PHP 8.2
php83 -v          # PHP 8.3
php84 -v          # PHP 8.4
php85 -v          # PHP 8.5
php -v            # Active PHP

# Composer Commands
cmp72 install     # Composer with PHP 7.2
cmp80 update      # Composer with PHP 8.0
cmp81 require laravel/sanctum  # Composer with PHP 8.1
cmp82 install     # Composer with PHP 8.2
cmp83 update      # Composer with PHP 8.3
cmp84 require --dev phpunit/phpunit  # Composer with PHP 8.4
cmp85 install     # Composer with PHP 8.5
cmp --version     # Composer with active PHP
```

**Use Cases**:

```bash
# Run Laravel with specific PHP version
php82 artisan serve

# Install dependencies with specific PHP
cmp83 install

# Run PHPUnit tests
php84 vendor/bin/phpunit

# Create new Laravel project
php81 composer create-project laravel/laravel my-app
```

---

### `php/add-php-path.ps1`

**Purpose**: Adds PHP to Windows system PATH environment variable.

**Features**:
- Detects installed PHP versions
- Adds selected PHP version to PATH
- Updates both User and System PATH
- Backs up existing PATH
- Shows current PATH configuration

**Usage**:

```powershell
# Run as Administrator
.\php\add-php-path.ps1

# Automatic detection of PHP versions:
# - Checks common locations (C:\PHP, C:\php, etc.)
# - Scans WAMP/XAMPP directories
# - Checks user PATH
# - Lists all found PHP versions

# Interactive selection:
# Select which PHP version to add to PATH
# Or add custom PHP directory path
```

---

## 🐳 Docker & Container Management

### Future Scripts (Planned)

```powershell
# docker-manager.ps1
# - List running containers
# - Start/Stop containers
# - Clean up unused containers
# - View logs
# - Manage Docker Compose projects

# docker-cleanup.ps1
# - Remove unused images
# - Clean volumes
# - Prune networks
# - System cleanup

# wsl-manager.ps1
# - Manage WSL distributions
# - Set default WSL version
# - Configure WSL settings
# - Import/Export WSL distros
```

---

## 🛠️ Windows System Scripts

### Future System Scripts

```powershell
# sys-info.ps1
# - Show system information
# - CPU, RAM, Disk usage
# - Windows version
# - Installed applications

# disk-cleanup.ps1
# - Clean temporary files
# - Empty recycle bin
# - Clear Windows temp
# - Remove browser cache

# env-manager.ps1
# - Manage environment variables
# - Add/Remove system PATH entries
# - Set user environment variables
# - Backup/Restore environment
```

---

## 📋 Installation Guide

### Prerequisites

- **Windows 7/8/10/11**
- **PowerShell 5.1 or higher**
- **Administrator privileges** (for some scripts)

### Quick Setup

```powershell
# 1. Clone or download the scripts
cd C:\projects\scripts

# 2. Run PHP Version Manager
powershell -ExecutionPolicy Bypass -File .\php\generate-php-bat-files.ps1

# 3. Verify installation
php -v
php82 -v
cmp --version
cmp82 --version
```

### Adding Scripts to PATH

```powershell
# To run scripts from anywhere, add to PATH:
# Method 1: Use the script
.\boot-up-apps.bat
# Select option 6 (Open startup folder)

# Method 2: Add manually
$env:Path += ";C:\projects\scripts\php"
[Environment]::SetEnvironmentVariable("Path", $env:Path, "User")
```

---

## 🔧 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Script not running** | Run PowerShell as Administrator |
| **Execution Policy error** | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| **PHP not found** | Ensure PHP is installed in common locations |
| **PATH not updating** | Restart terminal or log out/in |
| **Composer not found** | Install Composer globally first |
| **Permission denied** | Run scripts with Administrator privileges |

### Verification Commands

```powershell
# Check PHP installations
.\php\generate-php-bat-files.ps1
# Select option 1

# Check PATH
$env:Path -split ";"

# Check active PHP
php -v
cmp --version

# Check all PHP versions
Get-Command php* -ErrorAction SilentlyContinue
```

---

## 📝 Script-Specific Documentation

### PHP Scripts (`php/`)

For detailed documentation on PHP scripts, see:

- **[php/info.md](php/info.md)** - Complete PHP version management documentation
- **[php/add-php-path.ps1](php/add-php-path.ps1)** - PATH management helper

### General Scripts

- **[boot-up-apps.bat](boot-up-apps.bat)** - Startup application manager

---

## 🧪 Testing Your Setup

### PHP Version Testing

```bash
# Test all PHP versions
php72 -v
php80 -v
php81 -v
php82 -v
php83 -v
php84 -v
php85 -v

# Test Composer integration
cmp72 --version
cmp80 --version
cmp81 --version
cmp82 --version
cmp83 --version
cmp84 --version
cmp85 --version

# Test active commands
php -v
cmp --version
```

### Laravel Testing

```bash
# Create new Laravel project
php82 composer create-project laravel/laravel test-app
cd test-app

# Run migrations
php83 artisan migrate

# Start development server
php84 artisan serve
```

---

## 🤝 Contributing

Feel free to contribute by:

1. Adding new scripts
2. Improving existing scripts
3. Reporting issues
4. Suggesting features
5. Improving documentation

### Script Guidelines

- **Batch files** (.bat) - Use for simple Windows commands
- **PowerShell scripts** (.ps1) - Use for complex logic
- **Always test** scripts before committing
- **Include comments** and documentation
- **Handle errors** gracefully
- **Check for Administrator** privileges when needed

---

## 📚 Useful Resources

- [PHP Windows Downloads](https://windows.php.net/download/)
- [Composer](https://getcomposer.org/)
- [Laravel](https://laravel.com/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [Docker for Windows](https://docs.docker.com/desktop/windows/)

---

## 📝 License

This collection is provided as-is for development purposes. Use at your own risk.

---

## ✨ Quick Start Commands

```bash
# Quick reference for common commands

# PHP Version Manager
powershell -ExecutionPolicy Bypass -File .\php\generate-php-bat-files.ps1

# Add PHP to PATH
powershell -ExecutionPolicy Bypass -File .\php\add-php-path.ps1

# Boot-up apps manager
boot-up-apps.bat

# Run Laravel with specific PHP
php82 artisan serve

# Install dependencies
cmp83 install

# Run PHPUnit
php84 vendor/bin/phpunit
```

---

**Last Updated**: December 2024
**Maintained By**: Development Team