# powershell-modern loader

if ($ExecutionContext.SessionState.PSVariable.GetValue('global:PowerShellModernLoaded', $false)) {
    return
}
$global:PowerShellModernLoaded = $true

$powerShellModernTraceStartup = $env:POWERSHELL_MODERN_TRACE_STARTUP -eq '1'
if ($powerShellModernTraceStartup) {
    $powerShellModernStartupTimer = [Diagnostics.Stopwatch]::StartNew()
    $global:PowerShellModernStartupTimings = [Collections.Generic.List[object]]::new()
}

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
    if ($powerShellModernTraceStartup) {
        $powerShellModernModuleTimer = [Diagnostics.Stopwatch]::StartNew()
    }
    . $powerShellModernModule.FullName
    if ($powerShellModernTraceStartup) {
        $global:PowerShellModernStartupTimings.Add([PSCustomObject]@{
            Stage = $powerShellModernModule.Name
            Milliseconds = [Math]::Round($powerShellModernModuleTimer.Elapsed.TotalMilliseconds, 1)
        })
    }
}

Remove-Variable powerShellModernBinDir, powerShellModernPathEntries, powerShellModernModules, powerShellModernModule -ErrorAction SilentlyContinue
if ($powerShellModernTraceStartup) {
    $global:PowerShellModernStartupTimings.Add([PSCustomObject]@{
        Stage = 'Total (powershell-modern)'
        Milliseconds = [Math]::Round($powerShellModernStartupTimer.Elapsed.TotalMilliseconds, 1)
    })
    Remove-Variable powerShellModernStartupTimer, powerShellModernModuleTimer -ErrorAction SilentlyContinue
}
Remove-Variable powerShellModernTraceStartup -ErrorAction SilentlyContinue
