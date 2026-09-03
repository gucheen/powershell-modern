[CmdletBinding()]
param([switch] $KeepConfig)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'powershell\lib\Common.ps1')

$configDir = if ($env:POWERSHELL_MODERN_HOME) { $env:POWERSHELL_MODERN_HOME } else { Join-Path $HOME '.config\powershell-modern' }
$backupRoot = if ($env:POWERSHELL_MODERN_BACKUP_ROOT) { $env:POWERSHELL_MODERN_BACKUP_ROOT } else { Join-Path $HOME '.local\state\powershell-modern\backups' }
$profileFile = if ($env:POWERSHELL_MODERN_PROFILE) { $env:POWERSHELL_MODERN_PROFILE } else { $PROFILE.CurrentUserAllHosts }
$beginMarker = '# >>> powershell-modern >>>'
$endMarker = '# <<< powershell-modern <<<'

Assert-PowerShellModernPaths -ConfigDir $configDir -BackupRoot $backupRoot -ProfileFile $profileFile
$backup = New-PowerShellModernBackup -ConfigDir $configDir -BackupRoot $backupRoot -ProfileFile $profileFile
Write-Host "==> Backup saved to $backup"

if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
    $lines = @(Get-Content -LiteralPath $profileFile)
    $lines = @(Remove-PowerShellModernBlock -Lines $lines -BeginMarker $beginMarker -EndMarker $endMarker)
    Set-Content -LiteralPath $profileFile -Value $lines -Encoding UTF8
}
if (-not $KeepConfig -and (Test-Path -LiteralPath $configDir -PathType Container)) {
    Remove-Item -LiteralPath $configDir -Recurse -Force
}
Write-Host '==> Uninstall complete'
