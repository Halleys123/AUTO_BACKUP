# AUTO BACKUP - Junction-Only Sync for OneDrive

A PowerShell script that creates directory junctions (hard links) between folders on another drive and your OneDrive folder, without duplicating files.

## Features

- Creates junctions using mklink /J (not symbolic links)
- Never copies files - only creates directory links
- Skips excluded directories (like node_modules, .git)
- Removes orphaned items from OneDrive
- Protects specified items from deletion

## Usage

```powershell
.\JunctionOnlySync.ps1 -SourceRoot "E:\Projects" -DestRoot "$env:USERPROFILE\OneDrive\Projects"
```

## Parameters

- SourceRoot: Source directory (e.g., "E:\Projects")
- DestRoot: OneDrive destination directory
- ExcludeFile: Path to file with exclusion patterns (default: .\excludes.txt)
- ProtectFile: Path to file with protected patterns (default: .\protect.txt)
- DryRun: Preview changes without executing

## How It Works

1. Creates junctions for all directories in the source
2. Skips directories matching exclude patterns
3. Removes destination items that don't exist in source
4. Preserves items matching protect patterns
