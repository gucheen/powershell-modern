[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'powershell\lib\Common.ps1')

$configDir = if ($env:POWERSHELL_MODERN_HOME) {
    $env:POWERSHELL_MODERN_HOME
}
else {
    Join-Path $HOME '.config\powershell-modern'
}
$backupRoot = if ($env:POWERSHELL_MODERN_BACKUP_ROOT) {
    $env:POWERSHELL_MODERN_BACKUP_ROOT
}
else {
    Join-Path $HOME '.local\state\powershell-modern\backups'
}
$profileFile = if ($env:POWERSHELL_MODERN_PROFILE) {
    $env:POWERSHELL_MODERN_PROFILE
}
else {
    $PROFILE.CurrentUserAllHosts
}
$beginMarker = '# >>> powershell-modern >>>'
$endMarker = '# <<< powershell-modern <<<'

Assert-PowerShellModernPaths -ConfigDir $configDir -BackupRoot $backupRoot -ProfileFile $profileFile
$backup = New-PowerShellModernBackup -ConfigDir $configDir -BackupRoot $backupRoot -ProfileFile $profileFile
Write-Host "==> Backup saved to $backup"

$stage = "$configDir.stage.$PID"
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($directory in @('powershell.d', 'commands.d', 'bin', 'user')) {
    New-Item -ItemType Directory -Path (Join-Path $stage $directory) | Out-Null
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config\powershell-profile.ps1') -Destination (Join-Path $stage 'profile.ps1')
Copy-Item -Path (Join-Path $PSScriptRoot 'powershell\powershell.d\*.ps1') -Destination (Join-Path $stage 'powershell.d')
Copy-Item -Path (Join-Path $PSScriptRoot 'powershell\commands.d\*.ps1') -Destination (Join-Path $stage 'commands.d')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'powershell\bin\powershell-modern.ps1') -Destination (Join-Path $stage 'bin\powershell-modern.ps1')

if (Test-Path -LiteralPath (Join-Path $configDir 'user') -PathType Container) {
    Copy-Item -Path (Join-Path $configDir 'user\*') -Destination (Join-Path $stage 'user') -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $configDir) {
    Remove-Item -LiteralPath $configDir -Recurse -Force
}
Move-Item -LiteralPath $stage -Destination $configDir

$profileDirectory = Split-Path -Parent $profileFile
if ($profileDirectory) {
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
}
$profileLines = if (Test-Path -LiteralPath $profileFile -PathType Leaf) {
    @(Get-Content -LiteralPath $profileFile)
}
else {
    @()
}
$profileLines = @(Remove-PowerShellModernBlock -Lines $profileLines -BeginMarker $beginMarker -EndMarker $endMarker)
while ($profileLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($profileLines[$profileLines.Count - 1])) {
    if ($profileLines.Count -eq 1) {
        $profileLines = @()
    }
    else {
        $profileLines = @($profileLines[0..($profileLines.Count - 2)])
    }
}
if ($profileLines.Count -gt 0) {
    $profileLines += ''
}
$quotedConfigDir = $configDir.Replace("'", "''")
$profileLines += @(
    $beginMarker,
    "`$env:POWERSHELL_MODERN_HOME = '$quotedConfigDir'",
    "`$powershellModernProfile = Join-Path `$env:POWERSHELL_MODERN_HOME 'profile.ps1'",
    "if (Test-Path -LiteralPath `$powershellModernProfile) { . `$powershellModernProfile }",
    'Remove-Variable powershellModernProfile -ErrorAction SilentlyContinue',
    $endMarker
)
Set-Content -LiteralPath $profileFile -Value $profileLines -Encoding UTF8

Write-Host '==> Installation complete'
Write-Host 'Start a new PowerShell session or run: . $PROFILE.CurrentUserAllHosts'
Write-Host 'Check status with: powershell-modern doctor'
