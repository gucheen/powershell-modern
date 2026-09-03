Set-StrictMode -Version 2.0

function Assert-PowerShellModernPaths {
    param(
        [Parameter(Mandatory = $true)][string] $ConfigDir,
        [Parameter(Mandatory = $true)][string] $BackupRoot,
        [Parameter(Mandatory = $true)][string] $ProfileFile
    )

    if ([string]::IsNullOrWhiteSpace($HOME)) {
        throw 'HOME is unsafe or empty'
    }

    $homePath = [IO.Path]::GetFullPath($HOME).TrimEnd([IO.Path]::DirectorySeparatorChar)
    foreach ($candidate in @($ConfigDir, $BackupRoot)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            throw 'A managed path is empty'
        }
        $fullPath = [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ($fullPath -eq [IO.Path]::GetPathRoot($fullPath) -or $fullPath -eq $homePath) {
            throw "Unsafe managed path: $candidate"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ProfileFile)) {
        throw 'The PowerShell profile path is empty'
    }
}

function Remove-PowerShellModernBlock {
    param(
        [string[]] $Lines,
        [Parameter(Mandatory = $true)][string] $BeginMarker,
        [Parameter(Mandatory = $true)][string] $EndMarker
    )

    $managed = $false
    $result = [Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($line -eq $BeginMarker) {
            $managed = $true
            continue
        }
        if ($line -eq $EndMarker) {
            $managed = $false
            continue
        }
        if (-not $managed) {
            $result.Add($line)
        }
    }
    return $result.ToArray()
}

function New-PowerShellModernBackup {
    param(
        [Parameter(Mandatory = $true)][string] $ConfigDir,
        [Parameter(Mandatory = $true)][string] $BackupRoot,
        [Parameter(Mandatory = $true)][string] $ProfileFile
    )

    Assert-PowerShellModernPaths -ConfigDir $ConfigDir -BackupRoot $BackupRoot -ProfileFile $ProfileFile
    $stamp = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'), $PID
    $backup = Join-Path $BackupRoot $stamp
    New-Item -ItemType Directory -Path $backup -Force | Out-Null

    if (Test-Path -LiteralPath $ProfileFile -PathType Leaf) {
        Copy-Item -LiteralPath $ProfileFile -Destination (Join-Path $backup 'profile.ps1')
        Set-Content -LiteralPath (Join-Path $backup 'profile.present') -Value '1' -Encoding Ascii
    }
    else {
        Set-Content -LiteralPath (Join-Path $backup 'profile.present') -Value '0' -Encoding Ascii
    }

    if (Test-Path -LiteralPath $ConfigDir -PathType Container) {
        Copy-Item -LiteralPath $ConfigDir -Destination (Join-Path $backup 'config') -Recurse
        Set-Content -LiteralPath (Join-Path $backup 'config.present') -Value '1' -Encoding Ascii
    }
    else {
        Set-Content -LiteralPath (Join-Path $backup 'config.present') -Value '0' -Encoding Ascii
    }

    Set-Content -LiteralPath (Join-Path $backup 'config.path') -Value $ConfigDir -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $backup 'profile.path') -Value $ProfileFile -Encoding UTF8
    return $backup
}
