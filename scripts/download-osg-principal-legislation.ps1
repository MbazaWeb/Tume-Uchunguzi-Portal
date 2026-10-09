param(
  [string]$CollectionUuid = "62657fa2-7c35-4664-bcf1-88a01869d835",
  [string]$OutputDir = "public/docs/principal-legislation",
  [int]$MaxPages = 100,
  [switch]$InventoryOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$Base = "https://elibrary.osg.go.tz"
$CollectionUrl = "$Base/collections/$CollectionUuid/search"
$Headers = @{"User-Agent"="Mozilla/5.0 Katiba-Yetu-Law-Library/1.2";"Accept"="text/html,application/xhtml+xml"}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Slug([string]$s) {
  if (!$s) { return "document" }
  $s = $s.ToLowerInvariant() -replace '[^a-z0-9]+','-'
  $s = $s.Trim('-')
  if ($s.Length -gt 110) { $s = $s.Substring(0,110).Trim('-') }
  if (!$s) { return "document" }
  return $s
}
function Get-Html([string]$u) {
  return (Invoke-WebRequest -Uri $u -Headers $Headers -UseBasicParsing).Content
}
function Decode([string]$s) {
  return [System.Net.WebUtility]::HtmlDecode($s)
}

# OSG currently exposes item pages publicly even when some DSpace REST collection
# routes return 404. Inventory from the public collection UI, page by page.
$itemMap = @{}
for ($page=1; $page -le $MaxPages; $page++) {
  Write-Host "Inventory page $page..."
  $url = "${CollectionUrl}?spc.page=$page"
  try { $html = Get-Html $url } catch { throw "Could not open OSG collection page $page : $($_.Exception.Message)" }

  $matches = [regex]::Matches($html, 'href=["''](?:https://elibrary\.osg\.go\.tz)?/items/(?<uuid>[0-9a-fA-F-]{36})(?:[^"'']*)["'']', 'IgnoreCase')
  $new = 0
  foreach ($m in $matches) {
    $uuid = $m.Groups["uuid"].Value.ToLowerInvariant()
    if (!$itemMap.ContainsKey($uuid)) { $itemMap[$uuid] = $true; $new++ }
  }

  Write-Host "  Item links found: $($matches.Count); new: $new; total: $($itemMap.Count)"
  if ($new -eq 0 -and $page -gt 1) { break }
}

$uuids = @($itemMap.Keys | Sort-Object)
if ($uuids.Count -eq 0) {
  throw "OSG public collection returned 0 item links. No empty manifest was written."
}
Write-Host "Found $($uuids.Count) collection item(s)."

$manifest = @()
$counter = 0
foreach ($uuid in $uuids) {
  $counter++
  $itemUrl = "$Base/items/$uuid"
  try {
    $html = Get-Html $itemUrl
    $titleMatch = [regex]::Match($html, '<h1[^>]*>(?<t>.*?)</h1>', 'IgnoreCase,Singleline')
    if (!$titleMatch.Success) {
      $titleMatch = [regex]::Match($html, '<meta[^>]+property=["'']og:title["''][^>]+content=["''](?<t>[^"'']+)["'']', 'IgnoreCase')
    }
    $title = if ($titleMatch.Success) { (Decode ([regex]::Replace($titleMatch.Groups["t"].Value,'<[^>]+>',' ')) -replace '\s+',' ').Trim() } else { "OSG law $uuid" }
    Write-Host "[$counter/$($uuids.Count)] $title"

    $pdfMatches = [regex]::Matches($html, '(?<url>(?:https://elibrary\.osg\.go\.tz)?/server/api/core/bitstreams/(?<bit>[0-9a-fA-F-]{36})/content)', 'IgnoreCase')
    $seenBits = @{}
    foreach ($pm in $pdfMatches) {
      $bit = $pm.Groups["bit"].Value.ToLowerInvariant()
      if ($seenBits.ContainsKey($bit)) { continue }
      $seenBits[$bit] = $true

      $cap = $null
      if ($title -match '(?i)(?:chapter|cap\.?|sura(?:\s+ya)?)\s*[\.:,-]*\s*(\d+[A-Za-z]?)') { $cap = $Matches[1] }
      $prefix = if ($cap) { "cap-$cap" } else { "{0:D4}" -f $counter }
      $fileName = "$prefix-$(Slug $title).pdf"
      if ($seenBits.Count -gt 1) { $fileName = "$prefix-$(Slug $title)-$($seenBits.Count).pdf" }
      $path = Join-Path $OutputDir $fileName
      $contentUrl = if ($pm.Groups["url"].Value.StartsWith("http")) { $pm.Groups["url"].Value } else { $Base + $pm.Groups["url"].Value }

      if (!$InventoryOnly -and !(Test-Path $path)) {
        Invoke-WebRequest -Uri $contentUrl -OutFile $path -Headers @{"User-Agent"=$Headers["User-Agent"]} -UseBasicParsing
        $head = [System.IO.File]::ReadAllBytes($path) | Select-Object -First 4
        if ($head.Count -lt 4 -or $head[0] -ne 37 -or $head[1] -ne 80 -or $head[2] -ne 68 -or $head[3] -ne 70) {
          Remove-Item $path -Force
          throw "Downloaded content was not a PDF: $contentUrl"
        }
      }

      $hash = if (Test-Path $path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLowerInvariant() } else { $null }
      $manifest += [pscustomobject]@{
        title=$title; cap=$cap; item_uuid=$uuid; item_url=$itemUrl;
        bitstream_uuid=$bit; source_url=$contentUrl; file=$fileName;
        sha256=$hash; collection_uuid=$CollectionUuid
      }
    }
    if ($pdfMatches.Count -eq 0) { Write-Warning "No public PDF link found on item page: $itemUrl" }
  } catch {
    Write-Warning "Failed item $uuid : $($_.Exception.Message)"
  }
}

if ($manifest.Count -eq 0) {
  throw "Items were found, but no downloadable PDF links were discovered. No empty manifest was written."
}

$out = [pscustomobject]@{
  source="Office of the Solicitor General e-Library"; collection="Principal Legislation";
  collection_uuid=$CollectionUuid; collection_url=$CollectionUrl;
  generated_at_utc=[DateTime]::UtcNow.ToString("o"); item_count=$uuids.Count;
  pdf_count=$manifest.Count; documents=$manifest
}
$out | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $OutputDir "source-manifest.json")

if (!$InventoryOnly) {
  $library = @($manifest | Where-Object { Test-Path (Join-Path $OutputDir $_.file) } | ForEach-Object {
    $yr=$null; if ($_.title -match '\b(19|20)\d{2}\b') { $yr=[int]$Matches[0] }
    [pscustomobject]@{
      id=("source-"+(Slug $_.title)+"-"+$_.item_uuid.Substring(0,8)); title=$_.title; shortTitle=$_.title;
      chapterNumber=$(if($_.cap){$_.cap}else{"N/A"}); year=$yr; edition="Official source document";
      category="Principal Legislation"; source="Office of the Solicitor General e-Library";
      sourcePdf=("/docs/principal-legislation/"+$_.file); contentReady=$false;
      status="awaiting-conversion"; itemUrl=$_.item_url
    }
  })
  [pscustomobject]@{generated_at_utc=[DateTime]::UtcNow.ToString("o");documents=$library} |
    ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 "public/docs/library-index.json"
}

Write-Host "Done. PDFs discovered: $($manifest.Count)"
Write-Host "Manifest: $OutputDir/source-manifest.json"
if (!$InventoryOnly) { Write-Host "Frontend index: public/docs/library-index.json" }
