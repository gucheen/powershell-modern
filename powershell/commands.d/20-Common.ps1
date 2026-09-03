# @cmd Network | ports | Show listening TCP and UDP endpoints
function ports {
    $tcp = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            Protocol = 'TCP'
            LocalAddress = $_.LocalAddress
            LocalPort = $_.LocalPort
            ProcessId = $_.OwningProcess
        }
    }
    $udp = Get-NetUDPEndpoint -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            Protocol = 'UDP'
            LocalAddress = $_.LocalAddress
            LocalPort = $_.LocalPort
            ProcessId = $_.OwningProcess
        }
    }
    @($tcp) + @($udp) | Sort-Object Protocol, LocalPort
}

# @cmd System | mem | Show physical memory usage
function mem {
    $system = Get-CimInstance Win32_OperatingSystem
    $total = [double] $system.TotalVisibleMemorySize * 1KB
    $free = [double] $system.FreePhysicalMemory * 1KB
    [PSCustomObject]@{
        TotalGB = [Math]::Round($total / 1GB, 2)
        UsedGB = [Math]::Round(($total - $free) / 1GB, 2)
        FreeGB = [Math]::Round($free / 1GB, 2)
        UsedPercent = [Math]::Round((($total - $free) / $total) * 100, 1)
    }
}

# @cmd System | winlog <log-name> [lines] | Show recent Windows event log entries
function winlog {
    param([Parameter(Mandatory = $true)][string] $LogName, [int] $Lines = 100)
    if ($Lines -lt 1) {
        Write-Error 'usage: winlog <log-name> [lines]' -ErrorAction Continue
        return
    }
    Get-WinEvent -LogName $LogName -MaxEvents $Lines
}
