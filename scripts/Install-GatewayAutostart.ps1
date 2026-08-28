<#
.SYNOPSIS
    Make the Theocraft villager gateway start automatically when you log in.

.DESCRIPTION
    Creates (or removes) a shortcut in your Windows Startup folder that launches
    Run-LlmGateway.ps1 hidden at logon. No admin rights needed - it runs in your
    own user session (which the GPU and LAN binding require anyway).

.EXAMPLE
    .\scripts\Install-GatewayAutostart.ps1                 # install (chatterbox voice)
    .\scripts\Install-GatewayAutostart.ps1 -Voice piper    # install with a different voice
    .\scripts\Install-GatewayAutostart.ps1 -Uninstall      # remove autostart
#>
[CmdletBinding()]
param(
    [ValidateSet("auto", "chatterbox", "piper", "sapi", "none")]
    [string]$Voice = "chatterbox",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$runScript = Join-Path $repositoryRoot "scripts\Run-LlmGateway.ps1"
$startup = [Environment]::GetFolderPath("Startup")
$linkPath = Join-Path $startup "Theocraft villager gateway.lnk"

if ($Uninstall) {
    if (Test-Path -LiteralPath $linkPath) {
        Remove-Item -LiteralPath $linkPath -Force
        Write-Host "Removed autostart: $linkPath" -ForegroundColor Green
    } else {
        Write-Host "No autostart shortcut was installed." -ForegroundColor Yellow
    }
    return
}

# Launch powershell hidden, running the gateway with the chosen voice.
$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$runScript`" -Voice $Voice"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($linkPath)
$shortcut.TargetPath = $psExe
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $repositoryRoot
$shortcut.WindowStyle = 7          # minimized
$shortcut.Description = "Start the Theocraft villager LLM gateway at logon"
$shortcut.Save()

Write-Host "Installed autostart:" -ForegroundColor Green
Write-Host "  $linkPath"
Write-Host "  -> $psExe $arguments"
Write-Host ""
Write-Host "It will start next time you log in. To start it now without rebooting, run:" -ForegroundColor Cyan
Write-Host "  .\scripts\Run-LlmGateway.ps1 -Voice $Voice"
Write-Host "Remove it later with:  .\scripts\Install-GatewayAutostart.ps1 -Uninstall" -ForegroundColor DarkGray
