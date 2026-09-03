[CmdletBinding()]
param(
    [Parameter(Position = 0)][string] $Command = 'help',
    [Parameter(Position = 1)][string] $Target
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$configDir = if ($env:POWERSHELL_MODERN_HOME) { $env:POWERSHELL_MODERN_HOME } else { Join-Path $HOME '.config\powershell-modern' }
$backupRoot = if ($env:POWERSHELL_MODERN_BACKUP_ROOT) { $env:POWERSHELL_MODERN_BACKUP_ROOT } else { Join-Path $HOME '.local\state\powershell-modern\backups' }
$profileFile = if ($env:POWERSHELL_MODERN_PROFILE) { $env:POWERSHELL_MODERN_PROFILE } else { $PROFILE.CurrentUserAllHosts }
$beginMarker = '# >>> powershell-modern >>>'
$endMarker = '# <<< powershell-modern <<<'

function Assert-SafePaths {
    $homePath = [IO.Path]::GetFullPath($HOME).TrimEnd([IO.Path]::DirectorySeparatorChar)
    foreach ($candidate in @($configDir, $backupRoot)) {
        $fullPath = [IO.Path]::GetFullPath($candidate).TrimEnd([IO.Path]::DirectorySeparatorChar)
        if ([string]::IsNullOrWhiteSpace($candidate) -or $fullPath -eq [IO.Path]::GetPathRoot($fullPath) -or $fullPath -eq $homePath) {
            throw "Unsafe managed path: $candidate"
        }
    }
}

function New-Backup {
    Assert-SafePaths
    $stamp = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ'), $PID
    $backup = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
        Copy-Item -LiteralPath $profileFile -Destination (Join-Path $backup 'profile.ps1')
        Set-Content -LiteralPath (Join-Path $backup 'profile.present') -Value '1' -Encoding Ascii
    }
    else {
        Set-Content -LiteralPath (Join-Path $backup 'profile.present') -Value '0' -Encoding Ascii
    }
    if (Test-Path -LiteralPath $configDir -PathType Container) {
        Copy-Item -LiteralPath $configDir -Destination (Join-Path $backup 'config') -Recurse
        Set-Content -LiteralPath (Join-Path $backup 'config.present') -Value '1' -Encoding Ascii
    }
    else {
        Set-Content -LiteralPath (Join-Path $backup 'config.present') -Value '0' -Encoding Ascii
    }
    return $backup
}

function Show-Doctor {
    $failed = $false
    '{0,-18} {1}' -f 'item', 'status'
    '{0,-18} {1}' -f '----', '------'
    if (Test-Path -LiteralPath (Join-Path $configDir 'profile.ps1') -PathType Leaf) {
        '{0,-18} {1}' -f 'configuration', 'ok'
    }
    else {
        '{0,-18} {1}' -f 'configuration', 'missing'
        $failed = $true
    }
    $profileText = if (Test-Path -LiteralPath $profileFile -PathType Leaf) { Get-Content -LiteralPath $profileFile -Raw } else { '' }
    if ($profileText.Contains($beginMarker) -and $profileText.Contains($endMarker)) {
        '{0,-18} {1}' -f 'profile loader', 'ok'
    }
    else {
        '{0,-18} {1}' -f 'profile loader', 'missing'
        $failed = $true
    }
    '{0,-18} {1}' -f 'prompt', 'native PowerShell'
    $psReadLine = Get-Module -ListAvailable -Name PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
    if ($psReadLine) { '{0,-18} {1}' -f 'PSReadLine', $psReadLine.Version }
    else { '{0,-18} {1}' -f 'PSReadLine', 'missing' }
    if ($failed) { $global:LASTEXITCODE = 1 } else { $global:LASTEXITCODE = 0 }
}

function Restore-Backup {
    param([string] $RequestedTarget)
    Assert-SafePaths
    if ([string]::IsNullOrWhiteSpace($RequestedTarget)) {
        $backup = Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
        if (-not $backup) { throw 'No backup found' }
        $restorePath = $backup.FullName
    }
    elseif ([IO.Path]::IsPathRooted($RequestedTarget)) {
        $restorePath = $RequestedTarget
    }
    else {
        $restorePath = Join-Path $backupRoot $RequestedTarget
    }
    if (-not (Test-Path -LiteralPath $restorePath -PathType Container) -or
        -not (Test-Path -LiteralPath (Join-Path $restorePath 'profile.present')) -or
        -not (Test-Path -LiteralPath (Join-Path $restorePath 'config.present'))) {
        throw "Invalid backup: $restorePath"
    }

    $safety = New-Backup
    Write-Host "==> Current state saved to $safety"
    if ((Get-Content -LiteralPath (Join-Path $restorePath 'profile.present') -Raw).Trim() -eq '1') {
        $profileDirectory = Split-Path -Parent $profileFile
        if ($profileDirectory) { New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null }
        Copy-Item -LiteralPath (Join-Path $restorePath 'profile.ps1') -Destination $profileFile -Force
    }
    else {
        Remove-Item -LiteralPath $profileFile -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $configDir -Recurse -Force -ErrorAction SilentlyContinue
    if ((Get-Content -LiteralPath (Join-Path $restorePath 'config.present') -Raw).Trim() -eq '1') {
        Copy-Item -LiteralPath (Join-Path $restorePath 'config') -Destination $configDir -Recurse
    }
    Write-Host "==> Restored $restorePath"
}

function Show-Usage {
    @'
Usage: powershell-modern COMMAND [arguments]

Commands:
  doctor                  Show installed integrations.
  backup                  Back up the PowerShell profile and this environment.
  backups                 List available backups.
  rollback [name|path]    Restore a backup (latest when omitted).
'@
}

switch ($Command.ToLowerInvariant()) {
    'doctor' { Show-Doctor }
    'backup' { New-Backup }
    'backups' { Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -ExpandProperty FullName }
    'rollback' { Restore-Backup -RequestedTarget $Target }
    { $_ -in @('help', '-h', '--help') } { Show-Usage }
    default { throw "Unknown command: $Command" }
}
