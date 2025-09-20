<#
.SYNOPSIS
  Junction-only sync for OneDrive - creates directory junctions without copying files.

.DESCRIPTION
  Creates directory junctions (/J) for all directories except those matching exclude patterns.
  Never copies files - only creates junctions to avoid duplication.
  Removes destination items whose source is missing.

.PARAMETER SourceRoot
  Example: "E:\Projects"

.PARAMETER DestRoot
  Example: "$env:USERPROFILE\OneDrive\Projects"

.PARAMETER ExcludeFile
  Path to exclude patterns (one per line). Lines starting with # are comments.

.PARAMETER ProtectFile
  Optional path to protected patterns (one per line). Items matching these will NOT be deleted
  from destination even if source is missing.

.PARAMETER DryRun
  If specified, prints actions but does not change anything.

.EXAMPLE
  .\JunctionOnlySync.ps1 -SourceRoot "E:\Projects" -DestRoot "$env:USERPROFILE\OneDrive\Projects" -DryRun
#>

param(
    [string]$SourceRoot = "E:\Projects",
    [string]$DestRoot   = "$env:USERPROFILE\OneDrive\Projects",
    [string]$ExcludeFile = ".\excludes.txt",
    [string]$ProtectFile = ".\protect.txt",
    [switch]$DryRun
)

function Write-Action {
    param([string]$Message)
    if ($DryRun) { Write-Host "[DRYRUN] $Message" -ForegroundColor Yellow }
    else { Write-Host $Message }
}

# Validate source
if (-not (Test-Path -LiteralPath $SourceRoot)) {
    Write-Host "Source root not found: $SourceRoot" -ForegroundColor Red
    exit 1
}

# Ensure destination root exists
if (-not (Test-Path -LiteralPath $DestRoot)) {
    Write-Action "Would create destination root: $DestRoot"
    if (-not $DryRun) { New-Item -ItemType Directory -Path $DestRoot | Out-Null; Write-Host "Created destination root: $DestRoot" }
}

# Load excludes
$rawPatterns = @()
if (Test-Path -LiteralPath $ExcludeFile) {
    $rawPatterns = Get-Content -LiteralPath $ExcludeFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
} else {
    Write-Host "Exclude file not found at '$ExcludeFile' - using builtin defaults." -ForegroundColor Yellow
    $rawPatterns = @('node_modules', '.git', 'bin', 'obj', '*.exe', '*.log', '*.tmp')
}

# Load protect patterns (optional)
$rawProtect = @()
if (Test-Path -LiteralPath $ProtectFile) {
    $rawProtect = Get-Content -LiteralPath $ProtectFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
} else {
    $rawProtect = @()   # empty by default
}

# Classify exclude patterns into folder names and file patterns
$ExcludeFolderNames = @()
$ExcludeFilePatterns = @()
foreach ($p in $rawPatterns) {
    if ($p -match '[*?]') {
        $ExcludeFilePatterns += $p
    } elseif ($p.StartsWith('.') -and ($p -notmatch '[*?]')) {
        $ExcludeFolderNames += $p
    } elseif ($p -match '\.') {
        $ExcludeFilePatterns += $p
    } else {
        $ExcludeFolderNames += $p
    }
}

# Classify protect patterns similarly
$ProtectFolderNames = @()
$ProtectFilePatterns = @()
foreach ($p in $rawProtect) {
    if ($p -match '[*?]') {
        $ProtectFilePatterns += $p
    } elseif ($p.StartsWith('.') -and ($p -notmatch '[*?]')) {
        $ProtectFolderNames += $p
    } elseif ($p -match '\.') {
        $ProtectFilePatterns += $p
    } else {
        $ProtectFolderNames += $p
    }
}

function Test-FileExcluded {
    param([string]$FileName)
    foreach ($pat in $ExcludeFilePatterns) {
        if ($FileName -like $pat) { return $true }
    }
    return $false
}

function Test-FileProtected {
    param([string]$FileName)
    foreach ($pat in $ProtectFilePatterns) {
        if ($FileName -like $pat) { return $true }
    }
    return $false
}

function Test-Junction {
    param([string]$Path)
    try {
        $it = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($null -eq $it) { return $false }
        return (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch {
        return $false
    }
}

function Remove-Junction {
    param([string]$Path)
    try {
        $exists = Test-Path -LiteralPath $Path
        if (-not $exists) { return $true }

        $isJunction = $false
        try {
            $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
            $isJunction = (($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        } catch {
            $isJunction = $false
        }

        if ($isJunction) {
            $argument = '/c rmdir "{0}"' -f $Path
            $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $argument -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction Stop
            }
        } else {
            Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction Stop
        }

        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Test-Path -LiteralPath $Path)) { return $true }
            Start-Sleep -Milliseconds 100
        }

        try {
            $parent = [System.IO.Path]::GetDirectoryName($Path)
            $leaf = [System.IO.Path]::GetFileName($Path)
            $stamp = Get-Date -Format "yyyyMMddHHmmss"
            $newLeaf = "$leaf.__replaced__$stamp"
            $newFull = Join-Path $parent $newLeaf
            Move-Item -LiteralPath $Path -Destination $newFull -Force -ErrorAction Stop
            Write-Host "Info: junction moved aside to $newFull to unblock replacement" -ForegroundColor Yellow
            return $true
        } catch {
        }

        return (-not (Test-Path -LiteralPath $Path))
    } catch {
        return $false
    }
}

function New-Junction {
    param([string]$TargetPath, [string]$SourcePath)
    if (Test-Path -LiteralPath $TargetPath) {
        Write-Action "Destination exists, skipping junction create: $TargetPath"
        return
    }
    Write-Action "Creating junction: $TargetPath -> $SourcePath"
    if (-not $DryRun) {
        $quotedTarget = '"' + $TargetPath + '"'
        $quotedSource = '"' + $SourcePath + '"'
        $argument = "/c mklink /J $quotedTarget $quotedSource"
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $argument -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            Write-Host "mklink failed for: $TargetPath -> $SourcePath (exit $($proc.ExitCode))" -ForegroundColor Red
        }
    }
}

function Sync-Directory {
    param([string]$SrcPath, [string]$DstPath)

    # Skip if directory name is in exclude list
    $dirName = Split-Path -Leaf $SrcPath
    if ($ExcludeFolderNames -contains $dirName) {
        Write-Action "Skipping excluded directory: $SrcPath"
        return
    }

    # Create junction for this directory
    if (-not (Test-Path -LiteralPath $DstPath)) {
        New-Junction -TargetPath $DstPath -SourcePath $SrcPath
    } else {
        if (-not (Test-Junction -Path $DstPath)) {
            Write-Action "Destination exists as normal item (not junction): $DstPath (left as-is)"
        } else {
            Write-Action "Junction already exists: $DstPath"
        }
    }

    # Process subdirectories recursively
    Get-ChildItem -LiteralPath $SrcPath -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $childSrc = $_.FullName
        $childDst = Join-Path $DstPath $_.Name
        Sync-Directory -SrcPath $childSrc -DstPath $childDst
    }
}

# Run for each top-level project
Get-ChildItem -LiteralPath $SourceRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $projSrc = $_.FullName
    $projDst = Join-Path $DestRoot $_.Name
    Write-Host "`n>> Processing: $($_.Name)"
    Sync-Directory -SrcPath $projSrc -DstPath $projDst
}

# Cleanup: remove destination items whose source doesn't exist
function Remove-Orphans {
    param([string]$DestPath, [string]$SrcPath)

    Get-ChildItem -LiteralPath $DestPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $childDest = $_.FullName
        $childName = $_.Name
        $expectedSrc = Join-Path $SrcPath $childName

        if (-not (Test-Path -LiteralPath $expectedSrc)) {
            $isProtected = $false
            if ($ProtectFolderNames -contains $childName -or (Test-FileProtected -FileName $childName)) { 
                $isProtected = $true 
            }
            
            if ($isProtected) {
                Write-Action "Protected (source missing but protected): ${childDest} - skipping removal"
            } else {
                Write-Action "Remove destination item (source missing): ${childDest}"
                if (-not $DryRun) {
                    try { 
                        Remove-Item -LiteralPath $childDest -Recurse -Force -ErrorAction SilentlyContinue 
                    } catch { 
                        Write-Host ("Could not remove " + ${childDest} + ": " + $_) -ForegroundColor Red 
                    }
                }
            }
            return
        }

        # If it's a directory (not a junction), recurse inside
        if ($_.PSIsContainer) {
            $isReparse = (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            if (-not $isReparse) {
                Remove-Orphans -DestPath $childDest -SrcPath $expectedSrc
            }
        }
    }
}

Write-Host "`n>> Cleanup: removing destination items whose source is missing..."
Remove-Orphans -DestPath $DestRoot -SrcPath $SourceRoot

Write-Host "`nDone."