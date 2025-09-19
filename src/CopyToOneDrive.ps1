param(
    [string]$Source = "E:\Books",
    [string]$Destination = "C:\Users\arnav\OneDrive\Books",
    [string]$ExcludesFile = "E:\AUTO_BACKUP\excludes.txt"
)

# Read excludes
function Get-Excludes($file) {
    if (Test-Path $file) {
        return Get-Content $file | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
    }
    return @()
}

# Exclusion test
function Test-IsExcluded($path, $patterns) {
    foreach ($pattern in $patterns) {
        $leaf = Split-Path $path -Leaf
        if ($path -like "*\$pattern*" -or $leaf -like $pattern) {
            return $true
        }
    }
    return $false
}

$excludes = Get-Excludes $ExcludesFile

# Walk through files and create symlink if not exists
Get-ChildItem -Path $Source -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($Source.Length).TrimStart('\')
    $destPath = Join-Path $Destination $relativePath

    if (Test-IsExcluded $_.FullName $excludes) {
        Write-Host "Excluded: $relativePath"
        return
    }

    if ($_.PSIsContainer) {
        if (-not (Test-Path $destPath)) {
            New-Item -ItemType Directory -Path $destPath | Out-Null
            Write-Host "Created directory: $destPath"
        }
    } else {
        # ✅ SAFE FILE HANDLING START
        if (Test-Path $_.FullName) {
            try {
                if (-not (Test-Path $destPath)) {
                    New-Item -ItemType SymbolicLink -Path "$destPath" -Target "$($_.FullName)" -Force | Out-Null
                    Write-Host "Linked new file: $relativePath"
                } else {
                    $linkTarget = (Get-Item $destPath -Force).Target
                    if ($linkTarget -ne $_.FullName) {
                        Remove-Item $destPath -Force
                        New-Item -ItemType SymbolicLink -Path "$destPath" -Target "$($_.FullName)" -Force | Out-Null
                        Write-Host "Updated link: $relativePath"
                    }
                }
            }
            catch {
                Write-Warning "Failed to link $($_.FullName) -> $destPath. Error: $_"
            }
        } else {
            Write-Warning "Source file missing: $($_.FullName)"
        }
        # ✅ SAFE FILE HANDLING END
    }
}

Write-Host "Sync complete."