# powershell-modern loader

if ((Get-Variable -Name PowerShellModernLoaded -Scope Global -ErrorAction SilentlyContinue) -and
    $global:PowerShellModernLoaded) {
    return
}
$global:PowerShellModernLoaded = $true

if ([string]::IsNullOrWhiteSpace($env:POWERSHELL_MODERN_HOME)) {
    $env:POWERSHELL_MODERN_HOME = Join-Path $HOME '.config\powershell-modern'
}

$powerShellModernBinDir = Join-Path $env:POWERSHELL_MODERN_HOME 'bin'
$powerShellModernPathEntries = @($env:PATH -split [IO.Path]::PathSeparator)
if ($powerShellModernPathEntries -notcontains $powerShellModernBinDir) {
    $env:PATH = $powerShellModernBinDir + [IO.Path]::PathSeparator + $env:PATH
}

$powerShellModernModules = @(Get-ChildItem -LiteralPath (Join-Path $env:POWERSHELL_MODERN_HOME 'powershell.d') -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Sort-Object Name)
foreach ($powerShellModernModule in $powerShellModernModules) {
    . $powerShellModernModule.FullName
}

Remove-Variable powerShellModernBinDir, powerShellModernPathEntries, powerShellModernModules, powerShellModernModule -ErrorAction SilentlyContinue
