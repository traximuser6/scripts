# PHP Version Manager for Windows

## 📋 Overview

**PHP Version Manager** is a comprehensive PowerShell tool that simplifies managing multiple PHP versions on Windows systems. It automatically detects all PHP installations (from WAMP, XAMPP, custom directories, and PATH) and creates convenient batch files for easy switching between versions.

### 🎯 What It Does

- **Auto-discovers** all PHP installations on your system
- **Creates batch files** (`php72.bat`, `php80.bat`, etc.) for each PHP version
- **Generates Composer wrappers** (`cmp72.bat`, `cmp80.bat`, etc.) for each PHP version
- **Manages active PHP** version with simple commands
- **Handles duplicate installations** intelligently
- **Downloads and installs** new PHP versions from official Windows builds

---

## 🚀 Quick Start

### Installation

1. **Download** the `generate-php-bat-files.ps1` script
2. **Run** the script as Administrator:

```powershell
.\generate-php-bat-files.ps1
```

3. **Verify** installation by running:

```powershell
php -v
php80 -v
cmp --version
cmp82 --version
```

---

## 📦 Available Commands

### PHP Version Commands
| Command | Description |
|---------|-------------|
| `php72` | Run PHP 7.2 |
| `php80` | Run PHP 8.0 |
| `php81` | Run PHP 8.1 |
| `php82` | Run PHP 8.2 |
| `php83` | Run PHP 8.3 |
| `php84` | Run PHP 8.4 |
| `php85` | Run PHP 8.5 |
| `php` | Run active PHP version |

### Composer Version Commands
| Command | Description |
|---------|-------------|
| `cmp72` | Run Composer with PHP 7.2 |
| `cmp80` | Run Composer with PHP 8.0 |
| `cmp81` | Run Composer with PHP 8.1 |
| `cmp82` | Run Composer with PHP 8.2 |
| `cmp83` | Run Composer with PHP 8.3 |
| `cmp84` | Run Composer with PHP 8.4 |
| `cmp85` | Run Composer with PHP 8.5 |
| `cmp` | Run Composer with active PHP |

---

## 💡 Common Use Cases

### 1. Running Laravel with Specific PHP Version

```bash
# Run Laravel development server with PHP 8.2
php82 artisan serve

# Run Artisan commands with PHP 8.2
php82 artisan migrate
php82 artisan cache:clear

# Run Laravel with PHP 8.3
php83 artisan serve
```

### 2. Installing Dependencies with Specific PHP Version

```bash
# Install dependencies with PHP 8.2
cmp82 install

# Update dependencies with PHP 8.3
cmp83 update

# Run Composer commands
cmp82 require laravel/sanctum
cmp84 require --dev phpunit/phpunit
```

### 3. Running PHPUnit Tests

```bash
# Run tests with PHP 8.2
php82 vendor/bin/phpunit

# Run tests with PHP 8.3
php83 vendor/bin/phpunit
```

### 4. Switching Active PHP Version

```bash
# List all installed PHP versions
.\generate-php-bat-files.ps1
# Select option 1 to list versions

# Or use the interactive menu to switch
# Select option 3 from main menu
```

---

## 🛠️ Main Menu Options

When you run the script, you'll see an interactive menu:

```
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

### Menu Option Details

| Option | What It Does |
|--------|--------------|
| **1. List installed PHP versions** | Shows all PHP versions found on system |
| **2. Install / download PHP** | Downloads and installs new PHP version |
| **3. Switch active PHP** | Changes the active PHP version |
| **4. Show active PHP** | Displays current active PHP version details |
| **5. Remove PHP** | Uninstalls a PHP version |
| **6. Verify commands** | Checks if wrappers are working correctly |
| **7. Rebuild wrappers** | Regenerates all batch files |
| **8. PATH manager** | Manages PATH environment variable |
| **9. System information** | Shows system and PHP details |
| **10. Duplicate diagnostics** | Finds and handles duplicate PHP installations |
| **11. Exit** | Closes the manager |

---

## 📁 File Structure

```
C:\Users\YourUsername\.php-manager\
├── bin\                    # Batch files directory
│   ├── php72.bat           # PHP 7.2 wrapper
│   ├── php80.bat           # PHP 8.0 wrapper
│   ├── php81.bat           # PHP 8.1 wrapper
│   ├── php82.bat           # PHP 8.2 wrapper
│   ├── php83.bat           # PHP 8.3 wrapper
│   ├── php84.bat           # PHP 8.4 wrapper
│   ├── php85.bat           # PHP 8.5 wrapper
│   ├── cmp72.bat           # Composer for PHP 7.2
│   ├── cmp80.bat           # Composer for PHP 8.0
│   ├── cmp81.bat           # Composer for PHP 8.1
│   ├── cmp82.bat           # Composer for PHP 8.2
│   ├── cmp83.bat           # Composer for PHP 8.3
│   ├── cmp84.bat           # Composer for PHP 8.4
│   ├── cmp85.bat           # Composer for PHP 8.5
│   ├── php.bat             # Active PHP wrapper
│   ├── cmp.bat             # Active Composer wrapper
│   └── get-active-php.ps1  # Helper script
├── versions\               # Installed PHP versions
│   ├── 7.2.34\             # PHP 7.2.34 installation
│   ├── 8.2.12\             # PHP 8.2.12 installation
│   └── ...
├── downloads\              # Downloaded PHP ZIP files
├── registry.json           # PHP installations registry
└── active.json             # Active PHP configuration
```

---

## 🔧 Advanced Usage

### Installing a New PHP Version

```powershell
# Run the script
.\generate-php-bat-files.ps1

# Select option 2 (Install / download PHP)
# Enter version: 8.5.0
# Choose architecture: x64
# Choose Thread Safety: 1 (NTS) or 2 (TS)
```

### Managing Duplicate PHP Installations

The script automatically detects duplicate PHP installations and provides options to:

1. Keep only the canonical (best) version
2. Select specific version to keep and move others
3. Move all versions to manager directory
4. Skip and keep all

### PATH Management

The script automatically adds the `bin` directory to your User PATH, making all commands available globally.

---

## 🧪 Testing Your Setup

### Verify PHP Versions

```powershell
# Test each PHP version
php72 -v
php80 -v
php81 -v
php82 -v
php83 -v
php84 -v
php85 -v

# Test active PHP
php -v
```

### Verify Composer Integration

```powershell
# Test Composer with each PHP version
cmp72 --version
cmp80 --version
cmp81 --version
cmp82 --version
cmp83 --version
cmp84 --version
cmp85 --version

# Test active Composer
cmp --version
```

### Test with Laravel

```bash
# Create a new Laravel project with PHP 8.2
php82 composer create-project laravel/laravel my-project

cd my-project

# Run migrations with PHP 8.3
php83 artisan migrate

# Serve with PHP 8.4
php84 artisan serve
```

---

## ⚡ Performance Tips

1. **Cache Registry**: The script caches PHP detection results for faster subsequent runs
2. **Active Version**: Switching active PHP is instant (no file copying)
3. **Batch Files**: Wrappers are lightweight and execute quickly

---

## 🔍 Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `'php' is not recognized` | Run `.\generate-php-bat-files.ps1` as Administrator |
| `Access Denied` errors | Run PowerShell as Administrator |
| Composer not found | Install Composer globally first |
| PHP version not switching | Check `active.json` file permissions |
| Duplicate installations detected | Use option 10 to resolve duplicates |

### Manual Fixes

```powershell
# Force rebuild wrappers
.\generate-php-bat-files.ps1
# Select option 7 (Rebuild wrappers)

# Reset PATH
# Select option 8 (PATH manager) → option 1 (Add to User PATH)

# Re-scan for PHP installations
# Select option 7 (Rebuild wrappers) - this triggers a fresh scan
```

---

## 📚 Project Structure for Development

### For Laravel Projects

```bash
# .php-version file
8.2.12

# Or use wrapper commands in your workflow
php82 artisan serve
php82 artisan tinker
php82 artisan queue:work
```

### For WordPress Projects

```bash
# Use specific PHP version for development
php84 -S localhost:8080

# Or with custom port
php83 -S localhost:8000
```

---

## 🎯 Benefits

- **No More PATH Conflicts**: Each PHP version has its own wrapper
- **Easy Testing**: Test code with different PHP versions instantly
- **Project-Specific PHP**: Run each project with its required PHP version
- **Simple Commands**: Just use `php82` instead of full paths
- **Composer Integration**: Run Composer with any PHP version
- **WAMP/XAMPP Compatible**: Works with existing WAMP/XAMPP installations
- **Zero Configuration**: Auto-detects all PHP installations

---

## 🤝 Contributing

Feel free to contribute by:

1. Reporting issues
2. Suggesting features
3. Improving documentation
4. Testing with different PHP setups

---

## 📝 License

This script is provided as-is for PHP development management.

---

## ✨ Pro Tips

1. **Create Alias**: Add `alias phpm=".\generate-php-bat-files.ps1"` to your PowerShell profile
2. **Version Check**: Always verify PHP version before deployment
3. **CI/CD Integration**: Use wrapper commands in your CI/CD pipelines
4. **Multiple Projects**: Use different PHP versions for different projects simultaneously
5. **Quick Switch**: Change active PHP version in seconds

---

## 🔗 Related Commands

```bash
# Run PHP with specific configuration
php82 -c custom.ini script.php

# Run Composer with memory limit
cmp83 -d memory_limit=-1 install

# Debug with specific PHP version
php84 -r "echo phpinfo();"

# Run PHPUnit with specific PHP
php81 vendor/bin/phpunit --testsuite=Feature
```

---

**Happy PHP Version Management! 🚀**