# Stub initialization script. Customers replace with their software bootstrap.
$ErrorActionPreference = "Stop"
Write-Host "Initialize-WindowsSoftware running on $env:COMPUTERNAME"
$marker = "C:\\aib-marker.txt"
"Built by Azure Image Builder at $(Get-Date -Format o)" | Out-File -FilePath $marker -Force
Write-Host "Wrote marker file $marker"
