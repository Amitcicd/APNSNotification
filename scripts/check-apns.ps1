param(
  [int]$NotifyWindowDays = 7,
  [string]$MailSenderUpn = "Amit@webminesllc.us",
  [string]$MailRecipient = "Amit@webminesllc.us"
)

# Acquire Graph token from the already-authenticated GitHub OIDC session (azure/login)
$token = az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv
if (-not $token) { throw "Failed to acquire Graph token." }

$headers = @{ Authorization = "Bearer $token" }

# Get APNs (Apple MDM Push) certificate details from Graph
$apnsUrl = "https://graph.microsoft.com/v1.0/devicemanagement/applePushNotificationCertificate"
try {
  $apns = Invoke-RestMethod -Uri $apnsUrl -Headers $headers -Method GET -ErrorAction Stop
} catch {
  throw "Graph call for APNs failed: $($_.Exception.Message)"
}

if (-not $apns) { Write-Host "No APNs payload returned."; exit 0 }

$expiry = [datetime]::Parse($apns.expirationDateTime)
$now    = Get-Date
$days   = [int]([timespan]($expiry - $now)).TotalDays

Write-Host "APNs expiry: $expiry (Days left: $days)"

$needsNotify = $false
$subject = ""
$body    = ""

if ($expiry -lt $now) {
  $needsNotify = $true
  $subject = "MSIntune: IMPORTANT - Apple MDM Push certificate has expired"
  $body = @"
<p><b>ACTION REQUIRED</b>: The Apple MDM Push (APNs) certificate has <b>expired</b>.</p>
<p>Expiry: $expiry (Days left: $days)</p>
<p>Renew in Intune &gt; Tenant admin &gt; Apple MDM Push certificate.</p>
"@
}
elseif ($days -le $NotifyWindowDays) {
  $needsNotify = $true
  $subject = "MSIntune: Apple MDM Push certificate expires in $days day(s)"
  $body = @"
<p>Please take action before the Apple MDM Push (APNs) certificate expires.</p>
<p>Expiry: $expiry (Days left: $days)</p>
"@
}
else {
  Write-Host "APNs is healthy and outside the $NotifyWindowDays-day window."
}

if (-not $needsNotify) { exit 0 }

# Send email via Graph as the specified sender mailbox
$mailPayload = @{
  message = @{
    subject = $subject
    body = @{
      contentType = "HTML"
      content     = $body
    }
    toRecipients = @(@{ emailAddress = @{ address = $MailRecipient } })
  }
  saveToSentItems = $true
} | ConvertTo-Json -Depth 6

$sendUrl = "https://graph.microsoft.com/v1.0/users/$MailSenderUpn/sendMail"
try {
  Invoke-RestMethod -Uri $sendUrl -Method POST -Headers $headers -Body $mailPayload -ContentType "application/json" -ErrorAction Stop
  Write-Host "Notification email sent to $MailRecipient from $MailSenderUpn"
} catch {
  throw "Failed to send email via Graph: $($_.Exception.Message)"
}
