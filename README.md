# AUTO BACKUP

- A simple script to back up files and directories automatically to one drive.
- Similar to rclone but with a simpler interface you just tell it which files to back up and source destination that should be inside OneDrive folder.

```powershell
# Usage
./src/CopyToOneDrive.ps1 -Source "C:\path\to\source" -Destination "C:\path\to\OneDrive\Backup" -Exclude "C:\path\to\exclude"
./src/SyncToOneDrive.ps1 -Source "C:\path\to\source" -Destination "C:\path\to\OneDrive\Backup" -Exclude "C:\path\to\exclude"
```

## Sync vs Copy

| Command | Description                                                                                                                                                                                                |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Copy    | Copies files from source to destination. If a file already exists in the destination, it will be overwritten. It will not delete any files in the destination that are not present in the source.          |
| Sync    | Synchronizes files from source to destination. It will copy new and updated files from the source to the destination, and it will also delete files in the destination that are not present in the source. |

## Exclude Files

- You can exclude files or directories by using the `-Exclude` parameter.
- It takes path to a file that should contain list of files names or parameters similar to gitignore file.
- You can also use wildcards in the exclude file.

## Utility Scripts

1. CopyAll -> Use CopyToOneDrive.ps1 to copy some predefined folders to OneDrive.
2. SyncAll -> Use SyncToOneDrive.ps1 to sync some predefined folders to OneDrive.
