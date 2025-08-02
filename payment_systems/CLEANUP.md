# Payment Systems Cleanup Script

## Overview

The `cleanup.sh` script provides comprehensive cleanup functionality for the Payment Systems project. It safely removes temporary files, stops running processes, and cleans Docker resources while preserving all source code.

## Features

### 🔄 **Process Management**
- Stops all Node.js processes (backend, frontend, nodemon, vite)
- Terminates project-related processes
- Graceful shutdown with force kill fallback

### 🧹 **Temporary File Cleanup**
- **Build artifacts**: `dist/`, `build/`, `.next/`
- **Log files**: `*.log`, `npm-debug.log*`, `yarn-*.log*`
- **Temporary files**: `*.tmp`, `*.temp`, `.DS_Store`, `Thumbs.db`
- **Coverage reports**: `coverage/`, `.nyc_output/`
- **IDE files**: `.vscode/`, `.idea/`, `*.swp`, `*.swo`, `*~`
- **npm cache**: Cleans npm cache

### 🐳 **Docker Cleanup**
- Stops all running containers
- Removes all containers, images, and volumes
- Cleans custom networks
- Runs `docker system prune -af --volumes`

### 🗄️ **Database Cleanup**
- Removes SQLite database files (`*.db`, `*.sqlite`, `*.sqlite3`)
- Cleans database backup files

### 🔧 **Environment Cleanup**
- Removes `.env` files (preserves `.env.example`)
- Cleans environment-specific files

## Usage

### Direct Usage
```bash
./cleanup.sh
```

### Via Demo Script
```bash
./demo.sh full-cleanup
```

## Safety Features

### ✅ **Source Code Protection**
The script is designed to **NEVER** delete source code:
- All `.js`, `.jsx`, `.ts`, `.tsx` files preserved
- All `.html`, `.css`, `.scss` files preserved
- All `.json`, `.md`, `.txt` files preserved
- All configuration files preserved
- All source directories preserved

### 🔒 **Confirmation Prompt**
- Requires user confirmation before proceeding
- Shows what will be preserved
- Displays disk usage before and after

### 🛡️ **Error Handling**
- Graceful error handling for missing commands
- Continues cleanup even if some operations fail
- Safe process termination

## What Gets Cleaned

| Category | Items Removed | Preserved |
|----------|---------------|-----------|
| **Processes** | Node.js, Vite, npm processes | - |
| **Build Files** | `dist/`, `build/`, `.next/` | Source code |
| **Logs** | `*.log`, npm/yarn debug logs | - |
| **Temp Files** | `*.tmp`, `.DS_Store`, `Thumbs.db` | - |
| **IDE Files** | `.vscode/`, `.idea/`, swap files | - |
| **Databases** | `*.db`, `*.sqlite` files | - |
| **Environment** | `.env` files | `.env.example` |
| **Docker** | Containers, images, volumes | - |
| **Cache** | npm cache | - |

## What Gets Preserved

✅ **All source code files**  
✅ **Configuration files**  
✅ **Documentation**  
✅ **Package.json files**  
✅ **Git repository**  
✅ **Project structure**  

## Examples

### Basic Cleanup
```bash
./cleanup.sh
```

### Cleanup with Demo Script
```bash
./demo.sh full-cleanup
```

### After Cleanup
```bash
# Restart the application
./demo.sh dev
```

## Troubleshooting

### Permission Issues
```bash
chmod +x cleanup.sh
```

### Docker Not Found
The script will skip Docker cleanup if Docker is not installed.

### Process Already Killed
The script handles cases where processes are already terminated.

## Integration

The cleanup script is integrated with the main `demo.sh` script:

```bash
./demo.sh full-cleanup  # Runs comprehensive cleanup
./demo.sh clean         # Basic cleanup (processes + node_modules)
```

## Notes

- The script uses `find` commands with error suppression for safety
- All operations are logged with colored output
- Disk usage is shown before and after cleanup
- The script can be interrupted safely with Ctrl+C 