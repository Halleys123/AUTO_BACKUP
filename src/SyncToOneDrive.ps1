param(
    [string]$Source,        # e.g. "E:\Projects"
    [string]$Destination,   # e.g. "C:\Users\arnav\OneDrive\Projects"
    [string]$ExcludeFile = ".\excludes.txt"
)

function Get-Excludes($file) {
    if (Test-Path $file) {
        return Get-Content $file | Where-Object { $_ -and -not $_.StartsWith("#") }
    }
    return @()
}

function Test-IsExcluded($path, $patterns) {
    foreach ($pattern in $patterns) {
        $leaf = Split-Path $path -Leaf
        if ($path -like "*\$pattern*" -or $leaf -like $pattern) {
            return $true
        }
    }
    return $false
}


# Load exclude rules
$Excludes = Get-Excludes $ExcludeFile

# Ensure destination exists
if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination | Out-Null
}

# Sync from Source → Destination
Get-ChildItem -Recurse -Path $Source | ForEach-Object {
    $relativePath = $_.FullName.Substring($Source.Length).TrimStart('\')
    $destPath = Join-Path $Destination $relativePath

    if (Test-IsExcluded $_.FullName $Excludes) {
        Write-Host "Skipping excluded: $relativePath"
        return
    }

    if ($_ -is [System.IO.DirectoryInfo]) {
        if (-not (Test-Path $destPath)) {
            New-Item -ItemType Directory -Path $destPath | Out-Null
            Write-Host "Created directory: $destPath"
        }
    }
    else {
        if (-not (Test-Path $destPath)) {
            cmd /c mklink "$destPath" "$($_.FullName)" | Out-Null
            Write-Host "Linked file: $relativePath"
        }
    }
}

# Cleanup (remove links/folders in Destination if missing in Source)
Get-ChildItem -Recurse -Path $Destination | ForEach-Object {
    $relativePath = $_.FullName.Substring($Destination.Length).TrimStart('\')
    $srcPath = Join-Path $Source $relativePath

    if (-not (Test-Path $srcPath)) {
        Remove-Item $_.FullName -Force -Recurse
        Write-Host "Removed: $relativePath"
    }
}
