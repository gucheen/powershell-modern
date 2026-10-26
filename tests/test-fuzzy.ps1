Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$originalDefaultCommand = $env:FZF_DEFAULT_COMMAND
$originalDefaultOpts = $env:FZF_DEFAULT_OPTS
$originalOptsFile = $env:FZF_DEFAULT_OPTS_FILE
$originalExitCode = $ExecutionContext.SessionState.PSVariable.GetValue('global:LASTEXITCODE', 0)
$originalLocation = Get-Location
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("powershell-modern-fuzzy-$PID")
$global:PowerShellModernFuzzyTestState = @{
    Missing = @(); FdExit = 0; FzfExit = 0
    Candidates = @("中文 file's [1].txt"); Selection = "中文 file's [1].txt"
    FdArgs = @(); FzfArgs = @(); Input = @(); History = @()
    HistoryPath = Join-Path $fixtureRoot 'history.txt'
}
try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    # Mocks resolve only optional tools, keeping all other PowerShell commands real.
    function Get-Command {
        [CmdletBinding()]
        param([string] $Name, [string] $CommandType)
        if ($Name -in @('fd', 'fzf')) {
            if ($global:PowerShellModernFuzzyTestState.Missing -contains $Name) { return }
            $implementation = if ($Name -eq 'fd') {
                {
                    $global:PowerShellModernFuzzyTestState.FdArgs = @($args)
                    $global:LASTEXITCODE = $global:PowerShellModernFuzzyTestState.FdExit
                    $global:PowerShellModernFuzzyTestState.Candidates
                }
            }
            else {
                {
                    $global:PowerShellModernFuzzyTestState.FzfArgs = @($args)
                    $global:PowerShellModernFuzzyTestState.Input = @($input)
                    $global:LASTEXITCODE = $global:PowerShellModernFuzzyTestState.FzfExit
                    $global:PowerShellModernFuzzyTestState.Selection
                }
            }
            return [PSCustomObject]@{ Source = $implementation }
        }
        Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
    }
    function Get-PSReadLineOption { [PSCustomObject]@{ HistorySavePath = $global:PowerShellModernFuzzyTestState.HistoryPath } }
    function Get-History { $global:PowerShellModernFuzzyTestState.History }
    # Do not change the running test host's keyboard bindings.
    function Set-PSReadLineKeyHandler { param($Key, $BriefDescription, $ScriptBlock) }

    $source = Join-Path (Split-Path -Parent $PSScriptRoot) 'powershell\commands.d\30-FuzzyFind.ps1'
    $env:FZF_DEFAULT_COMMAND = 'custom file source'
    . $source
    if ($env:FZF_DEFAULT_COMMAND -ne 'custom file source') { throw 'Custom fzf source was overwritten' }
    $env:FZF_DEFAULT_COMMAND = ''
    . $source
    if ($env:FZF_DEFAULT_COMMAND -notmatch '^fd --type f') { throw 'fd default source was not configured' }

    $encoding = [Console]::OutputEncoding
    $result = ff -Query 'some query with spaces'
    if ($result -cne "中文 file's [1].txt") { throw 'File selection corrupted a path' }
    if ($global:PowerShellModernFuzzyTestState.FdArgs -notcontains 'f') { throw 'File selection did not request files' }
    if ($global:PowerShellModernFuzzyTestState.FzfArgs -notcontains '--query=some query with spaces') { throw 'Query was split into arguments' }
    if ([Console]::OutputEncoding.CodePage -ne $encoding.CodePage) { throw 'Console encoding was not restored' }

    $directory = Join-Path $fixtureRoot "中文 dir's [1]"
    New-Item -ItemType Directory -Path $directory | Out-Null
    Set-Location -LiteralPath $fixtureRoot
    $global:PowerShellModernFuzzyTestState.Candidates = @("中文 dir's [1]")
    $global:PowerShellModernFuzzyTestState.Selection = "中文 dir's [1]"
    cdf
    if ((Get-Location).Path -ne $directory) { throw 'Directory selection did not use a literal path' }
    if ($global:PowerShellModernFuzzyTestState.FdArgs -notcontains 'd') { throw 'Directory selection did not request directories' }
    Set-Location -LiteralPath $fixtureRoot
    foreach ($status in @(1, 130)) {
        $global:PowerShellModernFuzzyTestState.FzfExit = $status
        cdf
        if ((Get-Location).Path -ne $fixtureRoot) { throw 'Cancellation changed location' }
        if ($null -ne (ff)) { throw 'Cancellation returned a selection' }
    }
    $global:PowerShellModernFuzzyTestState.FzfExit = 2
    try { ff; throw 'fzf failure was ignored' }
    catch { if ($_.Exception.Message -notmatch 'fzf failed') { throw } }
    if ([Console]::OutputEncoding.CodePage -ne $encoding.CodePage) { throw 'Encoding was not restored after failure' }
    $global:PowerShellModernFuzzyTestState.FzfExit = 0
    $global:PowerShellModernFuzzyTestState.FdExit = 2
    try { ff; throw 'fd failure was ignored' }
    catch { if ($_.Exception.Message -notmatch 'fd failed') { throw } }
    $global:PowerShellModernFuzzyTestState.FdExit = 0

    $global:PowerShellModernFuzzyTestState.Candidates = @()
    $global:PowerShellModernFuzzyTestState.Input = @('not called')
    if ($null -ne (ff)) { throw 'Empty search returned a selection' }
    if ($global:PowerShellModernFuzzyTestState.Input -notcontains 'not called') { throw 'Empty search launched fzf' }

    foreach ($tool in @('fd', 'fzf')) {
        $global:PowerShellModernFuzzyTestState.Missing = @($tool)
        try { ff; throw 'Missing dependency was ignored' }
        catch { if ($_.Exception.Message -notmatch "$tool is required.*winget install") { throw } }
    }
    $global:PowerShellModernFuzzyTestState.Missing = @('fd', 'fzf')
    $env:FZF_DEFAULT_COMMAND = ''
    . $source
    if ($env:FZF_DEFAULT_COMMAND) { throw 'Missing fd configured an unusable default' }

    $global:PowerShellModernFuzzyTestState.Missing = @('fd')
    $global:PowerShellModernFuzzyTestState.History = @(
        [PSCustomObject]@{ CommandLine = 'git status' },
        [PSCustomObject]@{ CommandLine = 'Get-Date' }
    )
    Set-Content -LiteralPath $global:PowerShellModernFuzzyTestState.HistoryPath -Encoding UTF8 -Value @('git status', 'Get-ChildItem', 'Write-Host `', 'multiline')
    $global:PowerShellModernFuzzyTestState.Selection = 'git status'
    if ((fh git) -ne 'git status') { throw 'History selection failed without fd' }
    $expectedHistory = if (Get-Module PSReadLine) { @('Get-Date', 'git status', 'Get-ChildItem') } else { @('Get-Date', 'git status') }
    if (($global:PowerShellModernFuzzyTestState.Input -join '|') -ne ($expectedHistory -join '|')) { throw 'History order, deduplication or multiline filtering failed' }
    Remove-Item Function:\Get-Command
    if (Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue) {
        # Exercise the real native UTF-8 pipeline without opening an interactive UI.
        $env:FZF_DEFAULT_OPTS_FILE = ''
        $env:FZF_DEFAULT_OPTS = '--filter=中文'
        $result = Invoke-PowerShellModernFzf -Candidates @('other.txt', "中文 file's [1].txt")
        if ($result -cne "中文 file's [1].txt") { throw 'Native fzf UTF-8 pipeline failed' }
        $env:FZF_DEFAULT_OPTS = '--filter=no-match'
        if ($null -ne (Invoke-PowerShellModernFzf -Candidates @('other.txt'))) { throw 'Native fzf no-match handling failed' }
    }
    'fuzzy finder tests passed'
}
finally {
    Set-Location -LiteralPath $originalLocation.Path
    $env:FZF_DEFAULT_COMMAND = $originalDefaultCommand
    $env:FZF_DEFAULT_OPTS = $originalDefaultOpts
    $env:FZF_DEFAULT_OPTS_FILE = $originalOptsFile
    $global:LASTEXITCODE = $originalExitCode
    Remove-Variable PowerShellModernFuzzyTestState -Scope Global
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
