$global:PowerShellModernIsAdministrator = $false
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
    $global:PowerShellModernIsAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch {
    $global:PowerShellModernIsAdministrator = $false
}
Remove-Variable identity, principal -ErrorAction SilentlyContinue

$global:PowerShellModernGitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue

function Format-PowerShellModernPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$HomePath = $HOME
    )

    $separator = if ($Path.Contains('\')) { '\' } else { '/' }
    $prefix = ''
    $relativePath = $Path

    $isHome = -not [string]::IsNullOrEmpty($HomePath) -and
        ($Path.Equals($HomePath, [StringComparison]::OrdinalIgnoreCase) -or
         ($Path.Length -gt $HomePath.Length -and
          $Path.StartsWith($HomePath, [StringComparison]::OrdinalIgnoreCase) -and
          $Path[$HomePath.Length] -in @('\', '/')))
    if ($isHome) {
        $prefix = '~'
        $relativePath = $Path.Substring($HomePath.Length).TrimStart('\', '/')
    }
    elseif ($Path -match '^(\\\\[^\\/]+[\\/][^\\/]+)') {
        $prefix = $Matches[1]
        $relativePath = $Path.Substring($prefix.Length).TrimStart('\', '/')
    }
    elseif ($Path -match '^([A-Za-z]:[\\/])') {
        $prefix = $Matches[1]
        $relativePath = $Path.Substring($prefix.Length)
    }
    elseif ($Path.StartsWith('/')) {
        $prefix = '/'
        $relativePath = $Path.TrimStart('/')
    }

    $parts = @($relativePath -split '[\\/]' | Where-Object { $_ })
    for ($index = 0; $index -lt ($parts.Count - 1); $index++) {
        $parts[$index] = if ($parts[$index].StartsWith('.') -and $parts[$index].Length -gt 1) {
            $parts[$index].Substring(0, 2)
        }
        else {
            $parts[$index].Substring(0, 1)
        }
    }

    if ($parts.Count -eq 0) {
        return $prefix
    }

    $suffix = $parts -join $separator
    if (-not $prefix -or $prefix.EndsWith($separator)) {
        return $prefix + $suffix
    }
    return $prefix + $separator + $suffix
}

function Get-PowerShellModernGitStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not $global:PowerShellModernGitCommand) {
        return $null
    }

    try {
        $lines = @(& $global:PowerShellModernGitCommand.Path -C $Path status --porcelain=2 --branch 2>$null)
    }
    catch {
        return $null
    }
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $branch = $null
    $oid = $null
    $ahead = 0
    $behind = 0
    $staged = $false
    $modified = $false
    $untracked = $false

    foreach ($line in $lines) {
        if ($line.StartsWith('# branch.head ')) {
            $branch = $line.Substring(14)
        }
        elseif ($line.StartsWith('# branch.oid ')) {
            $oid = $line.Substring(13)
        }
        elseif ($line -match '^# branch\.ab \+(\d+) -(\d+)$') {
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
        }
        elseif ($line.StartsWith('1 ') -or $line.StartsWith('2 ')) {
            $xy = ($line -split ' ', 3)[1]
            $staged = $staged -or $xy[0] -ne '.'
            $modified = $modified -or $xy[1] -ne '.'
        }
        elseif ($line.StartsWith('u ')) {
            $staged = $true
            $modified = $true
        }
        elseif ($line.StartsWith('? ')) {
            $untracked = $true
        }
    }

    if ($branch -eq '(detached)' -and $oid -and $oid -ne '(initial)') {
        $branch = $oid.Substring(0, [Math]::Min(7, $oid.Length))
    }
    if (-not $branch) {
        return $null
    }

    [PSCustomObject]@{
        Branch = $branch
        Staged = $staged
        Modified = $modified
        Untracked = $untracked
        Ahead = $ahead
        Behind = $behind
    }
}

function global:prompt {
    $previousSucceeded = $?
    $previousExitCode = if (Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue) {
        $global:LASTEXITCODE
    }
    else {
        0
    }
    $userColor = if ($global:PowerShellModernIsAdministrator) { 'Red' } else { 'Gray' }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { [Environment]::UserName }
    $hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [Environment]::MachineName }
    $location = $ExecutionContext.SessionState.Path.CurrentLocation
    $displayPath = Format-PowerShellModernPath -Path $location.Path
    $gitStatus = if ($location.Provider.Name -eq 'FileSystem') {
        Get-PowerShellModernGitStatus -Path $location.Path
    }

    Write-Host "$userName@$hostName" -NoNewline -ForegroundColor $userColor
    Write-Host " $displayPath" -NoNewline -ForegroundColor Cyan
    if ($gitStatus) {
        $flags = ''
        if ($gitStatus.Staged) { $flags += '+' }
        if ($gitStatus.Modified) { $flags += '!' }
        if ($gitStatus.Untracked) { $flags += '?' }
        $divergence = ''
        if ($gitStatus.Ahead) { $divergence += " ↑$($gitStatus.Ahead)" }
        if ($gitStatus.Behind) { $divergence += " ↓$($gitStatus.Behind)" }
        $gitColor = if ($flags -or $divergence) { 'Yellow' } else { 'DarkGreen' }
        $flagText = if ($flags) { " $flags" } else { '' }
        Write-Host " [git:$($gitStatus.Branch)$flagText$divergence]" -NoNewline -ForegroundColor $gitColor
    }
    if (-not $previousSucceeded) {
        $failureCode = if ($previousExitCode) { $previousExitCode } else { 1 }
        Write-Host " [$failureCode]" -NoNewline -ForegroundColor Red
    }

    $global:LASTEXITCODE = $previousExitCode
    return ' $ '
}
