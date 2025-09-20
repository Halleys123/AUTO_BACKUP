<#
.SYNOPSIS
  Smart junction-based sync for OneDrive.

.DESCRIPTION
  Creates directory junctions (/J) for clean subtrees, descends into mixed trees,
  copies only small files (configurable), and removes destination items whose source is missing.

.PARAMETER SourceRoot
  Example: "E:\Projects"

.PARAMETER DestRoot
  Example: "$env:USERPROFILE\OneDrive\Projects"

.PARAMETER ExcludeFile
  Path to exclude patterns (one per line). Lines starting with # are comments.

.PARAMETER ProtectFile
  Optional path to protected patterns (one per line). Items matching these will NOT be deleted
  from destination even if source is missing.

.PARAMETER MaxCopySizeMB
  Max file size to copy (MB). Default 2 MB.

.PARAMETER DryRun
  If specified, prints actions but does not change anything.

.EXAMPLE
  .\SmartJunctionSync.ps1 -SourceRoot "E:\Projects" -DestRoot "$env:USERPROFILE\OneDrive\Projects" -DryRun
#>

param(
    [string]$SourceRoot = "E:\Projects",
    [string]$DestRoot   = "$env:USERPROFILE\OneDrive\Projects",
    [string]$ExcludeFile = ".\excludes.txt",
    [string]$ProtectFile = ".\protect.txt",
    [int]$MaxCopySizeMB = 2,
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

function Test-SubtreeExcluded {
    param([string]$Path)
    try {
        # check folder-name matches
        foreach ($name in $ExcludeFolderNames) {
            $found = Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($found) { return $true }
        }
        # check file-name patterns
        foreach ($pat in $ExcludeFilePatterns) {
            $foundFile = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -like $pat } | Select-Object -First 1
            if ($foundFile) { return $true }
        }
    } catch {
        # permissions/IO errors -> treat as clean (do not abort)
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
    # Try removing a junction robustly. Prefer cmd.exe rmdir to avoid provider quirks, then fallback.
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
                # fallback to PowerShell removal
                Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction Stop
            }
        } else {
            Remove-Item -LiteralPath $Path -Force -Recurse -ErrorAction Stop
        }

        # wait briefly for FS to settle
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Test-Path -LiteralPath $Path)) { return $true }
            Start-Sleep -Milliseconds 100
        }

        # If still present (e.g., locked by OneDrive), try renaming/moving the junction aside to unblock creation
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
            # Could not move either; give up
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

function Copy-SmallFile {
    param([string]$Src, [string]$Dst)
    Write-Action "Copy file: $Src -> $Dst"
    if (-not $DryRun) {
        # Use .NET Path APIs to avoid Split-Path parameter set ambiguity on Windows PowerShell 5.1
        $dFolder = [System.IO.Path]::GetDirectoryName($Dst)
        if ($null -ne $dFolder -and $dFolder -ne '') {
            if (-not (Test-Path -LiteralPath $dFolder)) { New-Item -ItemType Directory -Path $dFolder | Out-Null }
        }
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
    }
}

function Sync-Directory {
    param([string]$SrcPath, [string]$DstPath)

    $hasExcluded = $false
    try { $hasExcluded = Test-SubtreeExcluded -Path $SrcPath } catch { $hasExcluded = $false }

    if (-not $hasExcluded) {
        # safe: create one junction for this subtree
        if (-not (Test-Path -LiteralPath $DstPath)) {
            New-Junction -TargetPath $DstPath -SourcePath $SrcPath
        } else {
            if (-not (Test-Junction -Path $DstPath)) {
                Write-Action "Destination exists as normal item (not junction): $DstPath (left as-is)"
            } else {
                Write-Action "Junction already exists: $DstPath"
            }
        }
        return
    }

    # Mixed subtree: ensure real folder exists and handle children
    if (-not (Test-Path -LiteralPath $DstPath)) {
        Write-Action "Creating real folder: $DstPath"
        if (-not $DryRun) { New-Item -ItemType Directory -Path $DstPath | Out-Null }
    } else {
        # if a junction exists but we need a real folder, replace it
        if (Test-Junction -Path $DstPath) {
            Write-Action "Replacing existing junction with real folder: $DstPath"
            if (-not $DryRun) {
                $removed = Remove-Junction -Path $DstPath
                if (-not $removed) {
                    Write-Host "Warning: could not remove junction at $DstPath on first attempt" -ForegroundColor Yellow
                }
                # If path is gone, create it; if it still exists and is not a junction, we can keep it
                if (-not (Test-Path -LiteralPath $DstPath)) {
                    New-Item -ItemType Directory -Path $DstPath | Out-Null
                } else {
                    # Check if it is still a junction
                    $stillJunction = Test-Junction -Path $DstPath
                    if ($stillJunction) {
                        Write-Host "Warning: $DstPath is still a junction after removal attempts; leaving as-is." -ForegroundColor Yellow
                    } else {
                        Write-Action "Real folder already present: $DstPath"
                    }
                }
            }
        }
    }

    # Process immediate children
    Get-ChildItem -LiteralPath $SrcPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $childSrc = $_.FullName
        $childDst = Join-Path $DstPath $_.Name

        if ($_.PSIsContainer) {
            if ($ExcludeFolderNames -contains $_.Name) {
                Write-Action "Skipping excluded folder: $childSrc"
                return
            }
            Sync-Directory -SrcPath $childSrc -DstPath $childDst
        } else {
            if (Test-FileExcluded -FileName $_.Name) {
                Write-Action "Skipping excluded file: $childSrc"
                return
            }
            $sizeMB = [math]::Round( ($_.Length / 1MB), 2 )
            if ($_.Length -le ($MaxCopySizeMB * 1MB)) {
                if (-not (Test-Path -LiteralPath $childDst)) { Copy-SmallFile -Src $childSrc -Dst $childDst }
                else { Write-Action "File exists: $childDst" }
            } else {
                Write-Action "Skipping large file: $childSrc ($sizeMB MB)"
            }
        }
    }
}

# Run for each top-level project
Get-ChildItem -LiteralPath $SourceRoot -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $projSrc = $_.FullName
    $projDst = Join-Path $DestRoot $_.Name
    Write-Host "`n>> Processing: $($_.Name)"
    Sync-Directory -SrcPath $projSrc -DstPath $projDst
}

# NEW: Robust cleanup that DOES NOT follow junctions and removes dest items whose source doesn't exist.
function Remove-Orphans {
    param([string]$DestPath, [string]$SrcPath)

    # iterate children (do NOT use -Recurse here to avoid following junctions)
    Get-ChildItem -LiteralPath $DestPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $childDest = $_.FullName
        $childName = $_.Name
        $expectedSrc = Join-Path $SrcPath $childName

        # If expected source does not exist -> consider removal (unless protected)
        if (-not (Test-Path -LiteralPath $expectedSrc)) {
            # check protect rules: if name matches protect patterns, skip deletion
            $isProtected = $false
            if ($ProtectFolderNames -contains $childName -or (Test-FileProtected -FileName $childName)) { $isProtected = $true }
            if ($isProtected) {
                Write-Action "Protected (source missing but protected): ${childDest} - skipping removal"
            } else {
                Write-Action "Remove destination item (source missing): ${childDest}"
                if (-not $DryRun) {
                    try { Remove-Item -LiteralPath $childDest -Recurse -Force -ErrorAction SilentlyContinue } catch { Write-Host ("Could not remove " + ${childDest} + ": " + $_) -ForegroundColor Red }
                }
            }
            return
        }

        # If expected source exists and this dest entry is a directory (not a junction) -> recurse inside
        if ($_.PSIsContainer) {
            $isReparse = (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            if ($isReparse) {
                # it's a junction/symlink -> since expected source exists we leave it alone
                Write-Action "Found junction present and source exists: ${childDest}"
            } else {
                # normal directory -> recurse
                Remove-Orphans -DestPath $childDest -SrcPath $expectedSrc
            }
        } else {
            # file exists both sides -> nothing to do
        }
    }
}

Write-Host "`n>> Cleanup: removing destination items whose source is missing..."
Remove-Orphans -DestPath $DestRoot -SrcPath $SourceRoot

Write-Host "`nDone."
