Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("powershell-modern-test-$PID")
$testHome = Join-Path $testRoot 'home'
$env:POWERSHELL_MODERN_HOME = Join-Path $testHome '.config\powershell-modern'
$env:POWERSHELL_MODERN_BACKUP_ROOT = Join-Path $testHome '.local\state\powershell-modern\backups'
$env:POWERSHELL_MODERN_PROFILE = Join-Path $testHome 'profile.ps1'
$env:POWERSHELL_MODERN_COMMANDS_HOME = Join-Path $testHome 'private-commands'
New-Item -ItemType Directory -Path $testHome -Force | Out-Null
Set-Content -LiteralPath $env:POWERSHELL_MODERN_PROFILE -Value @('# original', 'function mine { $true }') -Encoding UTF8

try {
    . (Join-Path $projectRoot 'powershell\powershell.d\35-NativePrompt.ps1')
    $compactPath = Format-PowerShellModernPath -Path 'C:\Users\alice\projects\powershell-modern' -HomePath 'C:\Users\alice'
    if ($compactPath -ne '~\p\powershell-modern') { throw "Unexpected compact path: $compactPath" }
    $hiddenPath = Format-PowerShellModernPath -Path 'C:\Users\alice\.config\powershell-modern\user' -HomePath 'C:\Users\alice'
    if ($hiddenPath -ne '~\.c\p\user') { throw "Unexpected hidden path: $hiddenPath" }

    $sessionHistoryCount = $global:MaximumHistoryCount
    . (Join-Path $projectRoot 'powershell\powershell.d\00-PSReadLine.ps1')
    if ((Get-PSReadLineOption).MaximumHistoryCount -ne 50000) { throw 'PSReadLine history count was not configured' }
    if ($global:MaximumHistoryCount -ne $sessionHistoryCount) { throw 'PowerShell session history count was unexpectedly changed' }

    if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) {
        if (@($global:PowerShellModernGitCommand).Count -ne 1) { throw 'Git lookup must return a single executable' }
        $gitRoot = Join-Path $testRoot 'git-status'
        & git init --quiet $gitRoot
        & git -C $gitRoot config user.email 'powershell-modern@example.invalid'
        & git -C $gitRoot config user.name 'PowerShell Modern Tests'
        Set-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'initial' -Encoding UTF8
        & git -C $gitRoot add tracked.txt
        & git -C $gitRoot -c commit.gpgsign=false commit --quiet -m initial
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the Git test commit' }
        Add-Content -LiteralPath (Join-Path $gitRoot 'tracked.txt') -Value 'modified'
        Set-Content -LiteralPath (Join-Path $gitRoot 'staged.txt') -Value 'staged' -Encoding UTF8
        & git -C $gitRoot add staged.txt
        Set-Content -LiteralPath (Join-Path $gitRoot 'untracked.txt') -Value 'untracked' -Encoding UTF8
        $gitStatus = Get-PowerShellModernGitStatus -Path $gitRoot
        if (-not $gitStatus.Branch) { throw 'Git branch was not detected' }
        if (-not $gitStatus.Staged) { throw 'Staged Git change was not detected' }
        if (-not $gitStatus.Modified) { throw 'Modified Git change was not detected' }
        if (-not $gitStatus.Untracked) { throw 'Untracked Git file was not detected' }
    }

    & (Join-Path $projectRoot 'install.ps1')
    $profileText = Get-Content -LiteralPath $env:POWERSHELL_MODERN_PROFILE -Raw
    if (-not $profileText.Contains('# original')) { throw 'Original profile content was lost' }
    if ([regex]::Matches($profileText, [regex]::Escape('# >>> powershell-modern >>>')).Count -ne 1) { throw 'Managed block count is not one' }
    if (-not (Test-Path -LiteralPath (Join-Path $env:POWERSHELL_MODERN_HOME 'powershell.d\40-Abbreviations.ps1'))) { throw 'Abbreviation module is missing' }
    if (-not (Test-Path -LiteralPath (Join-Path $env:POWERSHELL_MODERN_HOME 'commands.d\20-Common.ps1'))) { throw 'Command library is missing' }

    # Use fresh processes so module caches and the loader guard cannot hide failures.
    $startupProbe = Join-Path $testRoot 'startup-probe.ps1'
    Set-Content -LiteralPath $startupProbe -Encoding UTF8 -Value @'
param([string] $Trace)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$env:POWERSHELL_MODERN_TRACE_STARTUP = $Trace
$loader = Join-Path $env:POWERSHELL_MODERN_HOME 'profile.ps1'
. $loader
if (-not (Get-Command ports -ErrorAction SilentlyContinue)) { throw 'Loader did not load commands' }
if ($Trace -eq '1') {
    $timings = $global:PowerShellModernStartupTimings
    $moduleCount = @(Get-ChildItem (Join-Path $env:POWERSHELL_MODERN_HOME 'powershell.d') -Filter '*.ps1').Count
    if ($timings.Count -ne ($moduleCount + 1)) { throw 'Startup timings are incomplete' }
    if ($timings[-1].Stage -ne 'Total (powershell-modern)') { throw 'Startup total is missing' }
    foreach ($timing in $timings) {
        if ($timing.Milliseconds -lt 0 -or $timing.Milliseconds -gt $timings[-1].Milliseconds) {
            throw 'Invalid startup timing'
        }
    }
    . $loader
    if (-not [object]::ReferenceEquals($timings, $global:PowerShellModernStartupTimings)) {
        throw 'Repeated loading replaced the startup timings'
    }
}
elseif (Get-Variable PowerShellModernStartupTimings -Scope Global -ErrorAction SilentlyContinue) {
    throw 'Startup tracing should be disabled by default'
}
'startup probe passed'
'@
    $shellExecutable = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }
    foreach ($trace in @('1', '0')) {
        $probeOutput = & $shellExecutable -NoLogo -NoProfile -File $startupProbe -Trace $trace
        if ($LASTEXITCODE -ne 0 -or $probeOutput -notcontains 'startup probe passed') { throw 'Startup probe failed' }
    }

    . (Join-Path $env:POWERSHELL_MODERN_HOME 'powershell.d\40-Abbreviations.ps1')
    abbr -Add gs Get-Service
    if (@(abbr -List) -notcontains 'gs') { throw 'Personal abbreviation was not added' }
    abbr -Define gs 'Get-Service -Name Spooler'
    if ($global:PowerShellModernAbbreviations['gs'] -ne 'Get-Service') { throw 'Shared abbreviation overrode a personal abbreviation' }
    abbr -Erase gs
    if ($global:PowerShellModernAbbreviations['gs'] -ne 'Get-Service -Name Spooler') { throw 'Shared abbreviation was not restored' }

    . (Join-Path $env:POWERSHELL_MODERN_HOME 'powershell.d\45-CommandLibrary.ps1')
    if (-not (Get-Command ports -ErrorAction SilentlyContinue)) { throw 'ports was not loaded' }
    if ((cmds network | Out-String) -notmatch 'ports') { throw 'Command discovery failed' }

    & (Join-Path $projectRoot 'install.ps1')
    if (-not (Test-Path -LiteralPath (Join-Path $env:POWERSHELL_MODERN_HOME 'user\abbreviations.json'))) { throw 'User abbreviations were not preserved' }

    $backup = & (Join-Path $env:POWERSHELL_MODERN_HOME 'bin\powershell-modern.ps1') backup
    Set-Content -LiteralPath $env:POWERSHELL_MODERN_PROFILE -Value '# changed' -Encoding UTF8
    & (Join-Path $env:POWERSHELL_MODERN_HOME 'bin\powershell-modern.ps1') rollback $backup
    if ((Get-Content -LiteralPath $env:POWERSHELL_MODERN_PROFILE -Raw) -notmatch '# original') { throw 'Rollback failed' }

    & (Join-Path $projectRoot 'uninstall.ps1')
    $profileText = Get-Content -LiteralPath $env:POWERSHELL_MODERN_PROFILE -Raw
    if ($profileText.Contains('# >>> powershell-modern >>>')) { throw 'Uninstall left the managed block behind' }
    if (Test-Path -LiteralPath $env:POWERSHELL_MODERN_HOME) { throw 'Uninstall left the configuration behind' }

    'all PowerShell tests passed'
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
