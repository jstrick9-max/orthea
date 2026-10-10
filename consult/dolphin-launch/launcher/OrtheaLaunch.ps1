# Orthea Consult - Dolphin toolbar launcher
#
# Dolphin Management runs this when staff click "Orthea Consult" in its Integrations pane,
# passing the open patient's details as arguments. It:
#   1. reads this practice's Orthea key from C:\ProgramData\Orthea\launch.key
#   2. sends the details + key to Orthea over HTTPS (n8n C04)
#   3. opens the one-time link Orthea returns in the default browser
# On any problem it shows a short message and stops.
#
# It never writes to Dolphin, its database, its folders or the registry. The only file it
# writes is a short log (date, time, result - no patient names) in %LOCALAPPDATA%\Orthea.
# Runs as the signed-in user; needs no admin rights. Written for Windows PowerShell 5.1.

param(
  [string]$Guid      = '',
  [string]$DolphinId = '',
  [string]$FirstName = '',
  [string]$LastName  = '',
  [string]$Birthday  = ''
)

$ErrorActionPreference = 'Stop'

# Dolphin passes each value as "=<value>" so a blank value is still an argument (Windows
# PowerShell drops empty "" arguments). Remove that leading "=" here.
function Get-Value([string]$v) { if ($v.StartsWith('=')) { $v.Substring(1) } else { $v } }
$Guid      = Get-Value $Guid
$DolphinId = Get-Value $DolphinId
$FirstName = Get-Value $FirstName
$LastName  = Get-Value $LastName
$Birthday  = Get-Value $Birthday

$Endpoint   = 'https://listen.ortheasecurity.com/webhook/consult/dolphin/launch'
$AllowedUrl = 'https://orthea-budibase.eqawdd.easypanel.host/'   # only links to Orthea are opened
$KeyFile    = Join-Path $env:ProgramData 'Orthea\launch.key'
$LogFile    = Join-Path $env:LOCALAPPDATA 'Orthea\launch.log'

# Test mode (developer use only): print instead of opening windows, use a local test endpoint.
$TestMode = ($env:ORTHEA_LAUNCH_TEST -eq '1')
if ($TestMode) {
  if ($env:ORTHEA_LAUNCH_ENDPOINT) { $Endpoint = $env:ORTHEA_LAUNCH_ENDPOINT }
  if ($env:ORTHEA_LAUNCH_KEYFILE)  { $KeyFile  = $env:ORTHEA_LAUNCH_KEYFILE }
  if ($env:ORTHEA_LAUNCH_LOGFILE)  { $LogFile  = $env:ORTHEA_LAUNCH_LOGFILE }
}

function Write-LaunchLog([string]$Message) {
  # Date, time and outcome only. Never patient names, IDs, the key or the link.
  try {
    $dir = Split-Path $LogFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogFile -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
  } catch { }
}

function Show-LaunchMessage([string]$Text) {
  if ($TestMode) { Write-Output "MESSAGE: $Text"; return }
  try {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($Text, 'Orthea Consult', 'OK', 'Warning')
  } catch { }
}

function Open-Link([string]$Url) {
  if ($TestMode) { Write-Output "OPEN: $Url"; return }
  Start-Process $Url
}

# --- 1. What Dolphin sent ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Guid) -and [string]::IsNullOrWhiteSpace($DolphinId)) {
  Write-LaunchLog 'stopped: Dolphin sent no patient'
  Show-LaunchMessage 'Dolphin did not send a patient. Open the patient in Dolphin, then click Orthea Consult again.'
  exit 1
}

# --- 2. This practice's key --------------------------------------------------------------
$Key = ''
try { $Key = (Get-Content -Path $KeyFile -Raw).Trim() } catch { }
if (-not $Key) {
  Write-LaunchLog 'stopped: no key file'
  Show-LaunchMessage 'Orthea Consult is not set up on this computer yet (no practice key). Please contact your Orthea administrator.'
  exit 1
}

# --- 3. Ask Orthea for the link ----------------------------------------------------------
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$Body = @{
  guid      = $Guid.Trim()
  dolphinId = $DolphinId.Trim()
  firstName = $FirstName.Trim()
  lastName  = $LastName.Trim()
  birthday  = $Birthday.Trim()
} | ConvertTo-Json -Compress

try {
  $Reply = Invoke-RestMethod -Method Post -Uri $Endpoint -TimeoutSec 20 `
             -Headers @{ 'X-Orthea-Key' = $Key } `
             -ContentType 'application/json; charset=utf-8' `
             -Body ([Text.Encoding]::UTF8.GetBytes($Body))
} catch {
  $Status = 0
  try { $Status = [int]$_.Exception.Response.StatusCode } catch { }
  if ($Status -eq 403) {
    Write-LaunchLog 'refused by Orthea (403)'
    Show-LaunchMessage 'Orthea did not accept this computer''s key, or the Dolphin link is switched off for the practice. Please contact your Orthea administrator.'
  } elseif ($Status -gt 0) {
    Write-LaunchLog "error from Orthea ($Status)"
    Show-LaunchMessage "Orthea could not open this patient right now (error $Status). Please try again in a minute, or open the patient from Orthea's patient list."
  } else {
    Write-LaunchLog 'could not reach Orthea'
    Show-LaunchMessage 'Could not reach Orthea. Check the internet connection and try again, or open the patient from Orthea''s patient list.'
  }
  exit 1
}

# --- 4. Open the link (only if it really is an Orthea Consult launch link) -----------------
if ($Reply -is [string]) { try { $Reply = $Reply | ConvertFrom-Json } catch { } }
$Url = ''
try { $Url = [string]$Reply.url } catch { }

if ($Url.StartsWith($AllowedUrl, [StringComparison]::OrdinalIgnoreCase) -and $Url.Contains('#/launch/')) {
  Write-LaunchLog ('opened (' + [string]$Reply.outcome + ')')
  Open-Link $Url
  exit 0
}

Write-LaunchLog 'unexpected reply from Orthea'
Show-LaunchMessage 'Orthea sent an unexpected reply. Please try again, or open the patient from Orthea''s patient list.'
exit 1
