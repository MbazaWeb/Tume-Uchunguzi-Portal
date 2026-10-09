param(
  [string]$CollectionUrl = "https://www.inec.go.tz/publications/election-laws",
  [string]$OutputDir = "public/docs/election-laws"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Write-Host "Fetching official INEC collection: $CollectionUrl"

$page = Invoke-WebRequest -Uri $CollectionUrl -UseBasicParsing
$base = [Uri]$CollectionUrl

function Get-Slug([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return "document" }
  $s = $Text.ToLowerInvariant()
  $s = $s -replace '[^a-z0-9]+','-'
  $s = $s.Trim('-')
  if ($s.Length -gt 90) { $s = $s.Substring(0,90).Trim('-') }
  if (-not $s) { $s = "document" }
  return $s
}

# Windows PowerShell and PowerShell 7 expose links differently, so parse hrefs
# from the official page and keep only INEC document uploads.
$matches = [regex]::Matches($page.Content, '<a[^>]+href=["''](?<href>[^"'']+/uploads/documents/[^"'']+)["''][^>]*>(?<text>.*?)</a>', 'IgnoreCase,Singleline')
if ($matches.Count -eq 0) {
  $matches = [regex]::Matches($page.Content, 'href=["''](?<href>[^"'']*uploads/documents/[^"'']+)["'']', 'IgnoreCase')
}

$seen = @{}
$items = @()
$counter = 0

foreach ($m in $matches) {
  $href = [System.Net.WebUtility]::HtmlDecode($m.Groups['href'].Value)
  if (-not $href) { continue }

  $uri = [Uri]::new($base, $href)
  if ($uri.Host -notmatch '(^|\.)inec\.go\.tz$') { continue }
  if ($uri.AbsolutePath -notmatch '\.pdf$') { continue }
  if ($seen.ContainsKey($uri.AbsoluteUri)) { continue }
  $seen[$uri.AbsoluteUri] = $true

  $counter++
  $rawTitle = if ($m.Groups['text'].Success) {
    ([regex]::Replace([System.Net.WebUtility]::HtmlDecode($m.Groups['text'].Value), '<[^>]+>', ' ') -replace '\s+',' ').Trim()
  } else { "" }

  $decodedOriginal = [Uri]::UnescapeDataString([IO.Path]::GetFileName($uri.AbsolutePath))
  $fallbackTitle = [IO.Path]::GetFileNameWithoutExtension($decodedOriginal)
  $title = if ($rawTitle) { $rawTitle } else { $fallbackTitle }
  $slug = Get-Slug $title
  $fileName = ('{0:D2}-{1}.pdf' -f $counter, $slug)
  $destination = Join-Path $OutputDir $fileName

  Write-Host ("[{0}] {1}" -f $counter, $title)
  Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $destination -UseBasicParsing

  $hash = (Get-FileHash -Algorithm SHA256 -Path $destination).Hash.ToLowerInvariant()
  $items += [pscustomobject]@{
    order = $counter
    title = $title
    file = $fileName
    source_url = $uri.AbsoluteUri
    collection_url = $CollectionUrl
    sha256 = $hash
    downloaded_at_utc = [DateTime]::UtcNow.ToString("o")
  }
}

if ($items.Count -eq 0) {
  throw "No INEC election-law PDFs were discovered. The source page structure may have changed."
}

$manifest = [pscustomobject]@{
  source = "Tume Huru ya Taifa ya Uchaguzi (INEC)"
  collection = "Sheria za Uchaguzi"
  collection_url = $CollectionUrl
  downloaded_at_utc = [DateTime]::UtcNow.ToString("o")
  document_count = $items.Count
  documents = $items
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutputDir "source-manifest.json")

Write-Host ""
Write-Host ("Downloaded {0} official PDF document(s) to {1}" -f $items.Count, $OutputDir)
Write-Host "Manifest: $OutputDir/source-manifest.json"
