param([Parameter(Mandatory=$true)][string[]]$Ids)
$ErrorActionPreference = 'Stop'
$records = foreach ($id in $Ids) {
  $url = "https://2e.aonprd.com/Equipment.aspx?ID=$id&NoRedirect=1"
  $html = (Invoke-WebRequest -Uri $url -TimeoutSec 30).Content
  $variants = foreach ($match in [regex]::Matches($html, '(?s)<h[12][^>]*class="title"[^>]*>(.*?)</h[12]>(.*?)(?=<h[12]\b|$)')) {
    $heading = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($match.Groups[1].Value, '<[^>]+>', ' ')) -replace '\s+', ' '
    $price = [regex]::Match($match.Groups[2].Value, '<b>Price</b>\s*([^<;]+)')
    if (-not $price.Success) { continue }
    $level = [regex]::Match($heading, 'Item\s+(\d+)')
    $source = [regex]::Match($match.Groups[2].Value, '(?s)<b>Source</b>\s*<a[^>]*>.*?<i>(.*?)</i>')
    [pscustomobject]@{
      name = ($heading -replace '\s*Item\s+\d+\+?.*$', '').Trim()
      level = if ($level.Success) { [int]$level.Groups[1].Value } else { $null }
      price_label = [System.Net.WebUtility]::HtmlDecode($price.Groups[1].Value).Trim()
      book = [System.Net.WebUtility]::HtmlDecode($source.Groups[1].Value)
    }
  }
  [pscustomobject]@{id="equipment-$id";url=$url;variants=@($variants)}
}
ConvertTo-Json -InputObject @($records) -Depth 6 -Compress
