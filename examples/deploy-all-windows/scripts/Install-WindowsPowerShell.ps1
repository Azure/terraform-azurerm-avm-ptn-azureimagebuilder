# Install PowerShell Core on Windows (PowerShell 7.x).
$ErrorActionPreference = "Stop"
$installerUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.6-win-x64.msi"
$installerPath = Join-Path $env:TEMP "pwsh-installer.msi"
Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait
Remove-Item $installerPath -Force
Write-Host "PowerShell Core installed."
