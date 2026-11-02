# Fills in App Store Connect for Blip with the App Store Connect API (no clicking).
# Windows PowerShell 5.1, nothing to install. Safe to run more than once: it skips what already exists.
#
#   powershell -ExecutionPolicy Bypass -File asc-setup.ps1 -KeyPath C:\path\AuthKey_QQV4MF4KGV.p8 [-Only iaps|listing] [-DryRun]
#
# What it does:
#   iaps:    creates the missing store products in asc-items.json (name, en-US text, US price, same countries
#            as the existing products) and uploads an App Review screenshot to every product that has none.
#   listing: fills the 1.0 version's en-US text (description, keywords, promo text, support URL),
#            subtitle + privacy policy URL, categories (Health & Fitness, then Games > Simulation),
#            and the App Review contact email + notes.
# Age rating and the App Privacy answers are not in the API: do those by hand in App Store Connect.
param(
  [Parameter(Mandatory=$true)][string]$KeyPath,
  [string]$Only = 'all',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg = Get-Content (Join-Path $here 'asc-items.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$listing = Get-Content (Join-Path $here 'listing.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$API = 'https://api.appstoreconnect.apple.com'

# ---------- auth: ES256 JWT signed with the .p8 key ----------
function B64Url([byte[]]$b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+','-').Replace('/','_') }
$pem = (Get-Content $KeyPath -Raw) -replace '-----[A-Z ]+-----','' -replace '\s',''
$cng = [Security.Cryptography.CngKey]::Import([Convert]::FromBase64String($pem), [Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob)
$ecdsa = New-Object Security.Cryptography.ECDsaCng($cng)
$ecdsa.HashAlgorithm = [Security.Cryptography.CngAlgorithm]::Sha256
$script:tokenAt = 0
function Token {
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  if ($now - $script:tokenAt -lt 600) { return $script:token }
  $h = B64Url ([Text.Encoding]::UTF8.GetBytes('{"alg":"ES256","kid":"' + $cfg.keyId + '","typ":"JWT"}'))
  $p = B64Url ([Text.Encoding]::UTF8.GetBytes('{"iss":"' + $cfg.issuer + '","iat":' + $now + ',"exp":' + ($now + 1100) + ',"aud":"appstoreconnect-v1"}'))
  $sig = B64Url ($ecdsa.SignData([Text.Encoding]::UTF8.GetBytes("$h.$p")))
  $script:token = "$h.$p.$sig"; $script:tokenAt = $now
  return $script:token
}
function Api([string]$method, [string]$path, $body) {
  $args2 = @{ Method = $method; Uri = ($API + $path); Headers = @{ Authorization = 'Bearer ' + (Token) } }
  if ($body) {
    $args2.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 20 -Compress))
    $args2.ContentType = 'application/json; charset=utf-8'
  }
  if ($DryRun -and $method -ne 'GET') { Write-Host "  [dry run] $method $path"; return $null }
  try { return Invoke-RestMethod @args2 }
  catch {
    $msg = $_.Exception.Message
    if ($_.Exception.Response) { $r = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg += ' ' + $r.ReadToEnd() }
    throw "$method $path failed: $msg"
  }
}
function All([string]$path) {  # follows paging
  $out = @(); $next = $path
  while ($next) { $r = Api GET $next; $out += $r.data; $next = if ($r.links.next) { $r.links.next.Replace($API, '') } else { $null } }
  return $out
}
$appId = $cfg.appId

# ---------- store products ----------
function Upload-Screenshot($iapId, [string]$file) {
  $bytes = [IO.File]::ReadAllBytes($file)
  $r = Api POST '/v1/inAppPurchaseAppStoreReviewScreenshots' @{ data = @{ type = 'inAppPurchaseAppStoreReviewScreenshots';
    attributes = @{ fileName = (Split-Path $file -Leaf); fileSize = $bytes.Length };
    relationships = @{ inAppPurchaseV2 = @{ data = @{ type = 'inAppPurchases'; id = $iapId } } } } }
  if (-not $r) { return }
  foreach ($op in $r.data.attributes.uploadOperations) {
    $chunk = New-Object byte[] $op.length; [Array]::Copy($bytes, $op.offset, $chunk, 0, $op.length)
    $hdr = @{}; $ct = 'application/octet-stream'
    foreach ($x in $op.requestHeaders) { if ($x.name -eq 'Content-Type') { $ct = $x.value } else { $hdr[$x.name] = $x.value } }
    Invoke-RestMethod -Method $op.method -Uri $op.url -Headers $hdr -ContentType $ct -Body $chunk | Out-Null
  }
  $md5 = ([BitConverter]::ToString((New-Object Security.Cryptography.MD5CryptoServiceProvider).ComputeHash($bytes))).Replace('-','').ToLower()
  Api PATCH ('/v1/inAppPurchaseAppStoreReviewScreenshots/' + $r.data.id) @{ data = @{ type = 'inAppPurchaseAppStoreReviewScreenshots'; id = $r.data.id;
    attributes = @{ uploaded = $true; sourceFileChecksum = $md5 } } } | Out-Null
}

if ($Only -eq 'all' -or $Only -eq 'iaps') {
  Write-Host '== Store products =='
  $have = @{}
  foreach ($x in (All "/v1/apps/$appId/inAppPurchasesV2?limit=200")) { $have[$x.attributes.productId] = $x }
  Write-Host ("Found {0} existing products" -f $have.Count)
  # Countries: copy from an existing product so every product sells in the same places.
  $template = $have.Values | Select-Object -First 1
  $territories = @()
  if ($template) {
    $av = Api GET ("/v2/inAppPurchases/" + $template.id + "/inAppPurchaseAvailability")
    if ($av.data) { $territories = All ("/v1/inAppPurchaseAvailabilities/" + $av.data.id + "/availableTerritories?limit=200") | ForEach-Object { @{ type = 'territories'; id = $_.id } } }
  }
  if (-not $territories.Count) { $territories = All '/v1/territories?limit=200' | ForEach-Object { @{ type = 'territories'; id = $_.id } } }
  Write-Host ("Selling in {0} countries" -f $territories.Count)

  foreach ($it in $cfg.items) {
    $iap = $have[$it.productId]
    if (-not $iap -and $it.create) {
      Write-Host ("+ Creating {0} ({1}, `${2})" -f $it.productId, $it.name, $it.price)
      $r = Api POST '/v2/inAppPurchases' @{ data = @{ type = 'inAppPurchases';
        attributes = @{ name = $it.name; productId = $it.productId; inAppPurchaseType = 'NON_CONSUMABLE'; familySharable = $false };
        relationships = @{ app = @{ data = @{ type = 'apps'; id = $appId } } } } }
      if (-not $r) { continue }
      $iap = $r.data; $id = $iap.id
      Api POST '/v1/inAppPurchaseLocalizations' @{ data = @{ type = 'inAppPurchaseLocalizations';
        attributes = @{ locale = 'en-US'; name = $it.name; description = $it.description };
        relationships = @{ inAppPurchaseV2 = @{ data = @{ type = 'inAppPurchases'; id = $id } } } } } | Out-Null
      $pp = (All "/v2/inAppPurchases/$id/pricePoints?filter[territory]=USA&limit=200") | Where-Object { $_.attributes.customerPrice -eq $it.price } | Select-Object -First 1
      if (-not $pp) { throw "No US price point for $($it.price)" }
      Api POST '/v1/inAppPurchasePriceSchedules' @{
        data = @{ type = 'inAppPurchasePriceSchedules'; relationships = @{
          inAppPurchase = @{ data = @{ type = 'inAppPurchases'; id = $id } };
          baseTerritory = @{ data = @{ type = 'territories'; id = 'USA' } };
          manualPrices = @{ data = @(@{ type = 'inAppPurchasePrices'; id = '${p1}' }) } } };
        included = @(@{ type = 'inAppPurchasePrices'; id = '${p1}'; attributes = @{ startDate = $null };
          relationships = @{ inAppPurchasePricePoint = @{ data = @{ type = 'inAppPurchasePricePoints'; id = $pp.id } } } }) } | Out-Null
      Api POST '/v1/inAppPurchaseAvailabilities' @{ data = @{ type = 'inAppPurchaseAvailabilities';
        attributes = @{ availableInNewTerritories = $true };
        relationships = @{ inAppPurchase = @{ data = @{ type = 'inAppPurchases'; id = $id } }; availableTerritories = @{ data = @($territories) } } } } | Out-Null
    }
    if (-not $iap) { Write-Host ("! {0} not found in App Store Connect, skipped" -f $it.productId); continue }
    $shot = Api GET ("/v2/inAppPurchases/" + $iap.id + "/appStoreReviewScreenshot")
    if ($shot -and $shot.data) { Write-Host ("  {0}: review screenshot already there" -f $it.productId); continue }
    Write-Host ("  {0}: uploading review screenshot" -f $it.productId)
    Upload-Screenshot $iap.id (Join-Path $here ('iap-screenshots\' + $it.screenshot))
  }
}

# ---------- store page ----------
if ($Only -eq 'all' -or $Only -eq 'listing') {
  Write-Host '== Store page =='
  $ver = (All "/v1/apps/$appId/appStoreVersions?filter[platform]=IOS&limit=50") | Where-Object { $_.attributes.appStoreState -in @('PREPARE_FOR_SUBMISSION','DEVELOPER_REJECTED','REJECTED','METADATA_REJECTED') } | Select-Object -First 1
  if (-not $ver) { throw 'No editable iOS version (expected 1.0 in Prepare for Submission)' }
  Write-Host ("Version {0}" -f $ver.attributes.versionString)
  $loc = (All ("/v1/appStoreVersions/" + $ver.id + "/appStoreVersionLocalizations")) | Where-Object { $_.attributes.locale -eq 'en-US' } | Select-Object -First 1
  Api PATCH ('/v1/appStoreVersionLocalizations/' + $loc.id) @{ data = @{ type = 'appStoreVersionLocalizations'; id = $loc.id;
    attributes = @{ description = $listing.description; keywords = $listing.keywords; promotionalText = $listing.promotionalText; supportUrl = $listing.supportUrl } } } | Out-Null
  Write-Host '  description, keywords, promo text, support URL set'

  $info = (All "/v1/apps/$appId/appInfos") | Where-Object { $_.attributes.appStoreState -ne 'READY_FOR_DISTRIBUTION' } | Select-Object -First 1
  Api PATCH ('/v1/appInfos/' + $info.id) @{ data = @{ type = 'appInfos'; id = $info.id; relationships = @{
    primaryCategory = @{ data = @{ type = 'appCategories'; id = 'HEALTH_AND_FITNESS' } };
    secondaryCategory = @{ data = @{ type = 'appCategories'; id = 'GAMES' } };
    secondarySubcategoryOne = @{ data = @{ type = 'appCategories'; id = 'GAMES_SIMULATION' } } } } } | Out-Null
  Write-Host '  categories: Health & Fitness, then Games > Simulation'
  $il = (All ("/v1/appInfos/" + $info.id + "/appInfoLocalizations")) | Where-Object { $_.attributes.locale -eq 'en-US' } | Select-Object -First 1
  Api PATCH ('/v1/appInfoLocalizations/' + $il.id) @{ data = @{ type = 'appInfoLocalizations'; id = $il.id;
    attributes = @{ subtitle = $listing.subtitle; privacyPolicyUrl = $listing.privacyPolicyUrl } } } | Out-Null
  Write-Host '  subtitle and privacy policy URL set'

  $rd = Api GET ("/v1/appStoreVersions/" + $ver.id + "/appStoreReviewDetail")
  $attrs = @{ contactEmail = $listing.contactEmail; notes = $listing.reviewNotes; demoAccountRequired = $false }
  if ($rd -and $rd.data) {
    Api PATCH ('/v1/appStoreReviewDetails/' + $rd.data.id) @{ data = @{ type = 'appStoreReviewDetails'; id = $rd.data.id; attributes = $attrs } } | Out-Null
  } else {
    Api POST '/v1/appStoreReviewDetails' @{ data = @{ type = 'appStoreReviewDetails'; attributes = $attrs;
      relationships = @{ appStoreVersion = @{ data = @{ type = 'appStoreVersions'; id = $ver.id } } } } } | Out-Null
  }
  Write-Host '  App Review contact email and notes set (name and phone: add by hand)'
}
Write-Host 'Done.'
