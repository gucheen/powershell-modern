# Optional tools are resolved when invoked, so installing them needs no profile reload.
function Get-PowerShellModernTool {
    param([string] $Name)
    $tool = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $tool) {
        $package = if ($Name -eq 'fd') { 'sharkdp.fd' } else { 'junegunn.fzf' }
        throw "powershell-modern: $Name is required. Install with: winget install --id $package --exact"
    }
    $tool.Source
}

function Invoke-PowerShellModernFzf {
    param(
        [string[]] $Candidates,
        [string] $Query = '',
        [string] $Prompt = '> ',
        [ValidateSet('default', 'reverse')][string] $Layout = 'reverse'
    )
    if (-not $Candidates -or $Candidates.Count -eq 0) { return }
    $fzf = Get-PowerShellModernTool 'fzf'
    $savedOutputEncoding = $OutputEncoding
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        # Windows PowerShell 5.1 otherwise sends non-ASCII pipeline input as '?'.
        $OutputEncoding = [Text.UTF8Encoding]::new($false)
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $selection = @($Candidates | & $fzf --height=40% "--layout=$Layout" --no-multi --no-print-query --no-expect --no-read0 --no-print0 "--prompt=$Prompt" "--query=$Query")
        $status = $LASTEXITCODE
        if ($status -in @(1, 130)) { return }
        if ($status -ne 0) { throw "powershell-modern: fzf failed (exit $status)" }
        if ($selection.Count -eq 1 -and $Candidates -ccontains $selection[0]) { $selection[0] }
    }
    finally {
        $OutputEncoding = $savedOutputEncoding
        [Console]::OutputEncoding = $savedConsoleEncoding
    }
}

function Select-PowerShellModernPath {
    param([ValidateSet('f', 'd')][string] $Type, [string] $Query = '')
    $fd = Get-PowerShellModernTool 'fd'
    $null = Get-PowerShellModernTool 'fzf'
    if ((Get-Location).Provider.Name -ne 'FileSystem') {
        throw 'powershell-modern: file selection requires a FileSystem location'
    }
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $candidates = @(& $fd --type $Type --color never --hidden --exclude .git .)
        if ($LASTEXITCODE -ne 0) { throw "powershell-modern: fd failed (exit $LASTEXITCODE)" }
    }
    finally { [Console]::OutputEncoding = $savedConsoleEncoding }
    Invoke-PowerShellModernFzf -Candidates $candidates -Query $Query -Prompt 'path> '
}

# @cmd Search | fd [pattern] [path] | Find files using the optional fd executable
# @cmd Search | fzf | Select pipeline input with the optional fuzzy finder
# @cmd Search | ff [query] | Fuzzy-select a file path using fd and fzf
function ff {
    param([string] $Query = '')
    Select-PowerShellModernPath -Type f -Query $Query
}

# @cmd Navigation | cdf [query] | Fuzzy-select a directory and change location
function cdf {
    param([string] $Query = '')
    $directory = Select-PowerShellModernPath -Type d -Query $Query
    if (-not [string]::IsNullOrEmpty($directory)) { Set-Location -LiteralPath $directory }
}

# @cmd Search | fh [query] | Fuzzy-select history without executing it
function fh {
    param([string] $Query = '')
    $null = Get-PowerShellModernTool 'fzf'
    $historyLines = [Collections.Generic.List[string]]::new()
    if (Get-Module PSReadLine) {
        $historyPath = (Get-PSReadLineOption).HistorySavePath
        if (Test-Path -LiteralPath $historyPath -PathType Leaf) {
            $pending = ''
            foreach ($line in (Get-Content -LiteralPath $historyPath -Encoding UTF8)) {
                # PSReadLine stores multiline commands with a trailing backtick.
                if ($line.EndsWith('`')) {
                    $pending += $line.Substring(0, $line.Length - 1) + "`n"
                }
                else {
                    $entry = $pending + $line
                    # The line-oriented selector only accepts complete single-line entries.
                    if (-not $pending -and $entry) { $historyLines.Add($entry) }
                    $pending = ''
                }
            }
        }
    }
    foreach ($entry in (Get-History)) {
        if ($entry.CommandLine -and $entry.CommandLine -notmatch '[\r\n]') { $historyLines.Add($entry.CommandLine) }
    }
    $historyLines.Reverse()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $candidates = @($historyLines | Where-Object { $seen.Add($_) })
    Invoke-PowerShellModernFzf -Candidates $candidates -Query $Query -Prompt 'history> ' -Layout default
}

if ((Get-Command fd -CommandType Application -ErrorAction SilentlyContinue) -and
    [string]::IsNullOrWhiteSpace($env:FZF_DEFAULT_COMMAND)) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --color never --hidden --exclude .git'
}

if ((Get-Module PSReadLine) -and (Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue)) {
    Set-PSReadLineKeyHandler -Key Ctrl+r -BriefDescription FuzzyHistory -ScriptBlock {
        $line = ''; $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor)
        try {
            $selection = fh -Query $line
            if ($selection) { [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $line.Length, $selection) }
        }
        catch { Write-Warning $_.Exception.Message }
    }
    if (Get-Command fd -CommandType Application -ErrorAction SilentlyContinue) {
        Set-PSReadLineKeyHandler -Key Ctrl+t -BriefDescription FuzzyFile -ScriptBlock {
            try {
                $selection = ff
                if ($selection) {
                    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("'" + $selection.Replace("'", "''") + "'")
                }
            }
            catch { Write-Warning $_.Exception.Message }
        }
        Set-PSReadLineKeyHandler -Key Alt+c -BriefDescription FuzzyDirectory -ScriptBlock {
            try { cdf; [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
            catch { Write-Warning $_.Exception.Message }
        }
    }
}
