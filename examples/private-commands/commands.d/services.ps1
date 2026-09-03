# @cmd Services | service-status <name> | Show a Windows service status
function service-status {
    param([Parameter(Mandatory = $true)][string] $Name)
    Get-Service -Name $Name
}
