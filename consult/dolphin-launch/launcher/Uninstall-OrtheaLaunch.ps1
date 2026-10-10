#Requires -RunAsAdministrator
# Orthea Consult - remove the Dolphin launcher from this workstation.
#   powershell -ExecutionPolicy Bypass -File .\Uninstall-OrtheaLaunch.ps1
# Removes C:\Program Files\Orthea and C:\ProgramData\Orthea. Remove the OrtheaConsult= line
# from dolphin.ini by hand (Dolphin closed), or restore your dolphin.ini backup.

$ErrorActionPreference = 'Stop'
foreach ($d in (Join-Path $env:ProgramFiles 'Orthea'), (Join-Path $env:ProgramData 'Orthea')) {
  if (Test-Path $d) { Remove-Item $d -Recurse -Force; Write-Host "Removed $d" }
}
Write-Host ''
Write-Host 'Now remove the OrtheaConsult= line from dolphin.ini (close Dolphin first), or restore the backup.' -ForegroundColor Yellow
