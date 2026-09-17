function Test-PowerShellModernPrivateSource {
    param([Parameter(Mandatory = $true)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    if ($env:OS -ne 'Windows_NT') {
        return $true
    }

    try {
        # Avoid importing Microsoft.PowerShell.Security on the startup path.
        # Read SIDs directly: resolving account names and translating them back
        # adds work and can involve domain lookups.
        $item = if ([IO.Directory]::Exists($Path)) {
            [IO.DirectoryInfo]::new($Path)
        }
        else {
            [IO.FileInfo]::new($Path)
        }
        $sections = [Security.AccessControl.AccessControlSections]'Owner, Access'
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $acl = [IO.FileSystemAclExtensions]::GetAccessControl(
                $item, $sections)
        }
        else {
            $acl = $item.GetAccessControl($sections)
        }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $currentSid = $identity.User.Value
        }
        finally {
            $identity.Dispose()
        }
        $ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($ownerSid -ne $currentSid) {
            return $false
        }

        $broadSids = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545')
        $writeRights = [Security.AccessControl.FileSystemRights]::Write -bor
            [Security.AccessControl.FileSystemRights]::Modify -bor
            [Security.AccessControl.FileSystemRights]::FullControl
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
                continue
            }
            $sid = $rule.IdentityReference.Value
            if ($broadSids -contains $sid -and (($rule.FileSystemRights -band $writeRights) -ne 0)) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

$global:PowerShellModernAbbreviations = [ordered]@{}
$global:PowerShellModernLocalAbbreviations = @{}
$global:PowerShellModernSharedAbbreviations = [ordered]@{}
$global:PowerShellModernAbbreviationFile = Join-Path $env:POWERSHELL_MODERN_HOME 'user\abbreviations.json'

if (Test-Path -LiteralPath $global:PowerShellModernAbbreviationFile -PathType Leaf) {
    $abbreviationDirectory = Split-Path -Parent $global:PowerShellModernAbbreviationFile
    if ((Test-PowerShellModernPrivateSource $abbreviationDirectory) -and
        (Test-PowerShellModernPrivateSource $global:PowerShellModernAbbreviationFile)) {
        try {
            $savedAbbreviations = Get-Content -LiteralPath $global:PowerShellModernAbbreviationFile -Raw | ConvertFrom-Json
            foreach ($property in $savedAbbreviations.PSObject.Properties) {
                $global:PowerShellModernAbbreviations[$property.Name] = [string] $property.Value
                $global:PowerShellModernLocalAbbreviations[$property.Name] = $true
            }
        }
        catch {
            Write-Warning "powershell-modern: could not read abbreviations: $($_.Exception.Message)"
        }
    }
    else {
        Write-Warning "powershell-modern: skipped a broadly writable or foreign-owned abbreviation file: $global:PowerShellModernAbbreviationFile"
    }
}

function Save-PowerShellModernAbbreviations {
    $directory = Split-Path -Parent $global:PowerShellModernAbbreviationFile
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $saved = [ordered]@{}
    foreach ($name in $global:PowerShellModernAbbreviations.Keys) {
        if ($global:PowerShellModernLocalAbbreviations.ContainsKey($name)) {
            $saved[$name] = $global:PowerShellModernAbbreviations[$name]
        }
    }
    $temporary = "$global:PowerShellModernAbbreviationFile.tmp.$PID"
    $saved | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $global:PowerShellModernAbbreviationFile -Force
}

function Show-PowerShellModernAbbreviationUsage {
    @'
Usage:
  abbr NAME EXPANSION...
  abbr -Add NAME EXPANSION...
  abbr -Define NAME EXPANSION...
  abbr -Erase NAME...
  abbr -Show [NAME...]
  abbr -List

Abbreviations expand when Space or Enter is pressed.
-Add persists a personal abbreviation; -Define declares one for this shell.
'@
}

function abbr {
    $arguments = @($args)
    $action = 'add'
    if ($arguments.Count -gt 0) {
        switch -Regex ([string] $arguments[0]) {
            '^(-a|-add|--add)$' { $arguments = @($arguments | Select-Object -Skip 1); break }
            '^(-d|-define|--define)$' { $action = 'define'; $arguments = @($arguments | Select-Object -Skip 1); break }
            '^(-e|-erase|--erase)$' { $action = 'erase'; $arguments = @($arguments | Select-Object -Skip 1); break }
            '^(-s|-show|--show)$' { $action = 'show'; $arguments = @($arguments | Select-Object -Skip 1); break }
            '^(-l|-list|--list)$' { $action = 'list'; $arguments = @($arguments | Select-Object -Skip 1); break }
            '^(-h|-help|--help)$' { Show-PowerShellModernAbbreviationUsage; return }
            '^-' { Write-Error "abbr: unknown option: $($arguments[0])" -ErrorAction Continue; return }
        }
    }
    elseif ($arguments.Count -eq 0) {
        $action = 'list'
    }

    switch ($action) {
        { $_ -in @('add', 'define') } {
            if ($arguments.Count -lt 2) {
                Write-Error (Show-PowerShellModernAbbreviationUsage) -ErrorAction Continue
                return
            }
            $name = [string] $arguments[0]
            if ($name -notmatch '^[A-Za-z0-9_.+-]+$') {
                Write-Error "abbr: invalid name: $name" -ErrorAction Continue
                return
            }
            $expansion = [string]::Join(' ', @($arguments | Select-Object -Skip 1))
            if ($expansion.Contains("`n") -or $expansion.Contains("`t")) {
                Write-Error 'abbr: expansion must be a single line without tabs' -ErrorAction Continue
                return
            }
            if ($action -eq 'define') {
                $global:PowerShellModernSharedAbbreviations[$name] = $expansion
                if (-not $global:PowerShellModernLocalAbbreviations.ContainsKey($name)) {
                    $global:PowerShellModernAbbreviations[$name] = $expansion
                }
            }
            else {
                $global:PowerShellModernAbbreviations[$name] = $expansion
                $global:PowerShellModernLocalAbbreviations[$name] = $true
                Save-PowerShellModernAbbreviations
            }
            break
        }
        'erase' {
            if ($arguments.Count -eq 0) {
                Write-Error 'abbr: -Erase requires a name' -ErrorAction Continue
                return
            }
            foreach ($name in $arguments) {
                $name = [string] $name
                if (-not $global:PowerShellModernLocalAbbreviations.ContainsKey($name)) {
                    Write-Error "abbr: $name is declared by a command pack; edit that source to remove it" -ErrorAction Continue
                    continue
                }
                $global:PowerShellModernAbbreviations.Remove($name)
                $global:PowerShellModernLocalAbbreviations.Remove($name)
                if ($global:PowerShellModernSharedAbbreviations.Contains($name)) {
                    $global:PowerShellModernAbbreviations[$name] = $global:PowerShellModernSharedAbbreviations[$name]
                }
            }
            Save-PowerShellModernAbbreviations
            break
        }
        'show' {
            foreach ($name in $global:PowerShellModernAbbreviations.Keys) {
                if ($arguments.Count -eq 0 -or $arguments -contains $name) {
                    "abbr -Add '$($name.Replace("'", "''"))' '$(([string] $global:PowerShellModernAbbreviations[$name]).Replace("'", "''"))'"
                }
            }
            break
        }
        'list' {
            $global:PowerShellModernAbbreviations.Keys
            break
        }
    }
}

function Expand-PowerShellModernAbbreviation {
    [string] $line = $null
    [int] $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref] $line, [ref] $cursor)
    $start = $cursor
    while ($start -gt 0 -and $line[$start - 1] -match '[A-Za-z0-9_.+-]') {
        $start--
    }
    if ($start -eq $cursor) {
        return
    }
    if ($start -gt 0 -and $line[$start - 1] -notmatch '[\s;|&()]') {
        return
    }

    $name = $line.Substring($start, $cursor - $start)
    $commandPrefix = $line.Substring(0, $start) -replace '^.*[;|&(]', ''
    if ($commandPrefix -match '^\s*abbr\s') {
        return
    }
    if ($global:PowerShellModernAbbreviations.Contains($name)) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace(
            $start,
            $cursor - $start,
            [string] $global:PowerShellModernAbbreviations[$name]
        )
    }
}

if (Get-Module -Name PSReadLine) {
    Set-PSReadLineKeyHandler -Key Spacebar -BriefDescription ExpandAbbreviation -ScriptBlock {
        param($key, $arg)
        Expand-PowerShellModernAbbreviation
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert(' ')
    }
    Set-PSReadLineKeyHandler -Key Enter -BriefDescription ExpandAbbreviationAndAccept -ScriptBlock {
        param($key, $arg)
        Expand-PowerShellModernAbbreviation
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}

Remove-Variable abbreviationDirectory, savedAbbreviations, property -ErrorAction SilentlyContinue
