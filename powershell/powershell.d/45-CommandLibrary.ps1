$global:PowerShellModernCommandSources = [Collections.Generic.List[string]]::new()

function Get-PowerShellModernCommandFiles {
    param(
        [Parameter(Mandatory = $true)][string] $Directory,
        [ValidateSet('managed', 'private')][string] $Trust = 'managed'
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }
    if ($Trust -eq 'private' -and -not (Test-PowerShellModernPrivateSource $Directory)) {
        Write-Warning "powershell-modern: skipped a broadly writable or foreign-owned command directory: $Directory"
        return
    }
    foreach ($file in (Get-ChildItem -LiteralPath $Directory -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($Trust -eq 'private' -and -not (Test-PowerShellModernPrivateSource $file.FullName)) {
            Write-Warning "powershell-modern: skipped a broadly writable or foreign-owned command source: $($file.FullName)"
            continue
        }
        $file.FullName
    }
}

function cmds {
    $arguments = @($args)
    if ($arguments.Count -gt 1) {
        Write-Error 'cmds: expected zero or one search term' -ErrorAction Continue
        return
    }
    $search = if ($arguments.Count -eq 1) { [string] $arguments[0] } else { '' }

    if ($search -in @('-h', '--help')) {
        "Usage: cmds [SEARCH]`n       cmds --sources"
        return
    }
    if ($search -eq '--sources') {
        $global:PowerShellModernCommandSources
        return
    }

    $commands = [Collections.Generic.List[object]]::new()
    foreach ($source in $global:PowerShellModernCommandSources) {
        foreach ($line in (Get-Content -LiteralPath $source)) {
            if ($line -notmatch '^\s*#\s*@cmd\s+(.+?)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*$') {
                continue
            }
            $item = [PSCustomObject]@{
                Category = $Matches[1].Trim()
                Signature = $Matches[2].Trim()
                Description = $Matches[3].Trim()
            }
            $haystack = "$($item.Category) $($item.Signature) $($item.Description)"
            if ([string]::IsNullOrWhiteSpace($search) -or $haystack.IndexOf($search, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $commands.Add($item)
            }
        }
    }

    if ($commands.Count -eq 0) {
        Write-Error "cmds: no commands match '$search'" -ErrorAction Continue
        return
    }

    $categories = [Collections.Generic.List[string]]::new()
    foreach ($command in $commands) {
        if (-not $categories.Contains($command.Category)) {
            $categories.Add($command.Category)
        }
    }
    foreach ($category in $categories) {
        $group = @($commands | Where-Object Category -eq $category)
        $width = ($group | ForEach-Object { $_.Signature.Length } | Measure-Object -Maximum).Maximum
        $category
        $format = '  {0,-' + $width + '}  {1}'
        foreach ($command in $group) {
            $format -f $command.Signature, $command.Description
        }
        ''
    }
}

$managedCommandDirectory = Join-Path $env:POWERSHELL_MODERN_HOME 'commands.d'
foreach ($commandSource in (Get-PowerShellModernCommandFiles -Directory $managedCommandDirectory)) {
    . $commandSource
    $global:PowerShellModernCommandSources.Add($commandSource)
}

if ([string]::IsNullOrWhiteSpace($env:POWERSHELL_MODERN_COMMANDS_HOME)) {
    $env:POWERSHELL_MODERN_COMMANDS_HOME = Join-Path $HOME '.config\powershell-modern-commands'
}
$privateCommands = $env:POWERSHELL_MODERN_COMMANDS_HOME
if (Test-Path -LiteralPath $privateCommands -PathType Container) {
    if (Test-PowerShellModernPrivateSource $privateCommands) {
        foreach ($commandSource in (Get-PowerShellModernCommandFiles -Directory (Join-Path $privateCommands 'commands.d') -Trust private)) {
            . $commandSource
            $global:PowerShellModernCommandSources.Add($commandSource)
        }
        $privateAbbreviations = Join-Path $privateCommands 'abbreviations.ps1'
        if (Test-Path -LiteralPath $privateAbbreviations -PathType Leaf) {
            if (Test-PowerShellModernPrivateSource $privateAbbreviations) {
                . $privateAbbreviations
                $global:PowerShellModernCommandSources.Add($privateAbbreviations)
            }
            else {
                Write-Warning "powershell-modern: skipped a broadly writable or foreign-owned command source: $privateAbbreviations"
            }
        }
    }
    else {
        Write-Warning "powershell-modern: skipped a broadly writable or foreign-owned command directory: $privateCommands"
    }
}

$localConfig = Join-Path $env:POWERSHELL_MODERN_HOME 'user\local.ps1'
if (Test-Path -LiteralPath $localConfig -PathType Leaf) {
    $localDirectory = Split-Path -Parent $localConfig
    if ((Test-PowerShellModernPrivateSource $localDirectory) -and (Test-PowerShellModernPrivateSource $localConfig)) {
        . $localConfig
        $global:PowerShellModernCommandSources.Add($localConfig)
    }
    else {
        Write-Warning "powershell-modern: skipped a broadly writable or foreign-owned local config source: $localConfig"
    }
}

Remove-Variable managedCommandDirectory, commandSource, privateCommands, privateAbbreviations, localConfig, localDirectory -ErrorAction SilentlyContinue
