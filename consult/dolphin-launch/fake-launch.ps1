# Orthea — fake Dolphin launch, for testing C04 before any launcher exists.
# Run in PowerShell on your PC:  powershell -ExecutionPolicy Bypass -File .\fake-launch.ps1
# Paste the practice key below first (from consult.create_launch_key). Don't save the key in the repo.

$Key = 'PASTE-PRACTICE-KEY-HERE'
$Url = 'https://listen.ortheasecurity.com/webhook/consult/dolphin/launch'

# A made-up Dolphin patient (the same shape Dolphin's toolbar tokens give us)
$Body = @{
  key       = $Key
  guid      = '{8DEB5881-00BC-4F30-8BCF-798E892B9602}'
  dolphinId = 'TESTER'
  firstName = 'Test'
  lastName  = 'Patient'
  birthday  = '07/15/1987'
} | ConvertTo-Json

try {
  $r = Invoke-RestMethod -Method Post -Uri $Url -Headers @{ 'X-Orthea-Key' = $Key } `
         -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Body))
  Write-Host "Matched by: $($r.outcome)"
  Write-Host "Open within 2 minutes: $($r.url)"
} catch {
  Write-Host "Refused ($($_.Exception.Response.StatusCode.value__)): $($_.ErrorDetails.Message)"
}
