function ll {
    Get-ChildItem -Force @args
}

function la {
    Get-ChildItem -Force @args
}

function powershell-modern {
    & (Join-Path $env:POWERSHELL_MODERN_HOME 'bin\powershell-modern.ps1') @args
}
