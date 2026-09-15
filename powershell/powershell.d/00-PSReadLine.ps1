if (-not (Get-Module -Name PSReadLine)) {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
}

if (Get-Module -Name PSReadLine) {
    Set-PSReadLineOption -HistorySaveStyle SaveIncrementally -MaximumHistoryCount 50000 -HistoryNoDuplicates:$true

    try {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle InlineView
    }
    catch {
        # Prediction options require a recent PSReadLine and a host with prediction support.
    }

    Set-PSReadLineKeyHandler -Key RightArrow -Function ForwardChar
    Set-PSReadLineKeyHandler -Key Ctrl+f, Alt+f -Function ForwardWord
    Set-PSReadLineKeyHandler -Key End -Function EndOfLine
    Set-PSReadLineKeyHandler -Key Alt+Backspace -Function BackwardKillWord
}
