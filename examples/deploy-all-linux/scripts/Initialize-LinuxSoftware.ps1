#!/usr/bin/env pwsh
# Stub initialization script. Customers replace with their software bootstrap.
Write-Host "Initialize-LinuxSoftware running on $(hostname)"
$marker = "/opt/aib-marker.txt"
"Built by Azure Image Builder at $(Get-Date -Format o)" | Out-File -FilePath $marker -Force
Write-Host "Wrote marker file $marker"
