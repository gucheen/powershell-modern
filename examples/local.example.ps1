# Copy this file to ~/.config/powershell-modern/user/local.ps1.
$DevelopmentRoot = 'C:\src'

# @cmd Local | cdev | Change to the local development directory
function cdev {
    Set-Location -LiteralPath $DevelopmentRoot
}
