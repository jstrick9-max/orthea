#Requires -RunAsAdministrator
# Orthea Consult - install the Dolphin launcher on this workstation.
#
# Run from an elevated (Administrator) PowerShell, in the folder holding these files:
#   powershell -ExecutionPolicy Bypass -File .\Install-OrtheaLaunch.ps1
#
# What it does (and nothing else):
#   C:\Program Files\Orthea\OrtheaLaunch.ps1   the launcher (only admins can change it)
#   C:\Program Files\Orthea\orthea.bmp         the toolbar icon
#   C:\ProgramData\Orthea\launch.key           the practice key (staff can read, only admins can change)
# It does NOT touch Dolphin or dolphin.ini: it prints the line to add, which you add by hand.
# Undo with Uninstall-OrtheaLaunch.ps1.

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
$App  = Join-Path $env:ProgramFiles 'Orthea'
$Data = Join-Path $env:ProgramData 'Orthea'

foreach ($f in 'OrtheaLaunch.ps1', 'orthea.bmp') {
  if (-not (Test-Path (Join-Path $Here $f))) { throw "Missing $f next to this installer." }
}

# The key is typed or pasted here, hidden, and never shown on screen.
$Secure = Read-Host 'Paste the practice key (starts with olk_)' -AsSecureString
$Key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)).Trim()
if ($Key -notmatch '^olk_[0-9a-f]{64}$') { throw 'That does not look like an Orthea practice key (olk_ followed by 64 characters). Nothing was installed.' }

New-Item -ItemType Directory -Path $App, $Data -Force | Out-Null
Copy-Item (Join-Path $Here 'OrtheaLaunch.ps1') $App -Force
Copy-Item (Join-Path $Here 'orthea.bmp') $App -Force
Unblock-File (Join-Path $App 'OrtheaLaunch.ps1')

$KeyFile = Join-Path $Data 'launch.key'
Set-Content -Path $KeyFile -Value $Key -Encoding ASCII -NoNewline
# SYSTEM and Administrators: full control. Users: read only. (SIDs, so any Windows language works.)
& icacls.exe $KeyFile /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' '*S-1-5-32-545:R' | Out-Null

$Ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Line = 'OrtheaConsult=Orthea Consult,Open this patient in Orthea Consult,' + (Join-Path $App 'orthea.bmp') + ',' +
        $Ps + ' -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $App 'OrtheaLaunch.ps1') + '"' +
        ' -Guid "={PatientGUID}" -DolphinId "={PatientID}" -FirstName "={PatientFirstName}" -LastName "={PatientLastName}" -Birthday "={PatientBirthday}"'

Write-Host ''
Write-Host 'Installed. Nothing in Dolphin has changed yet.' -ForegroundColor Green
Write-Host ''
Write-Host 'To add the button: close Dolphin on this PC, back up dolphin.ini, then add this ONE line'
Write-Host 'under [Toolbar] in dolphin.ini, exactly as shown (it is all one line):'
Write-Host ''
Write-Host $Line -ForegroundColor Cyan
Write-Host ''
