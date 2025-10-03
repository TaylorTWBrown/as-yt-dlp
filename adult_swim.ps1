param(
    [Parameter(Mandatory = $true)]
    [string]$ShowName,

    [switch]$Download
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseUrl = "https://www.adultswim.com/videos/$ShowName"
$userAgent = 'Mozilla/5.0 (Windows NT)'

try {
    $resp = Invoke-WebRequest -Uri $baseUrl -Headers @{ 'User-Agent' = $userAgent } -ErrorAction Stop
} catch {
    Write-Error "Failed to fetch the page $baseUrl - $($_.Exception.Message)"
    exit 1
}

$html = $resp.Content

function SafeName($s) {
    if (-not $s) { return '' }
    return ($s -replace '[\\/:*?"<>|]', '') -replace '\s{2,}', ' ' -replace '^\s+|\s+$',''
}

function MakeSeasonToken($seasonRaw) {
    if (-not $seasonRaw) { return 'S01' }
    $raw = $seasonRaw.Trim()
    if ($raw -match '^\d{4}$') { return "S$raw" }
    if ($raw -match '^\d+$') { return ('S{0:00}' -f [int]$raw) }
    $safe = SafeName $raw
    if ($safe) { return 'S' + $safe }
    return 'S01'
}

# Find H2 tags and the HTML that follows each until the next H2 (document order)
# We create an array of objects: @{ SeasonLabel = <string>; SectionHtml = <string> }
$h2SplitRx = [regex]::new('(?is)(<h2\b[^>]*>.*?</h2>)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$parts = @()

# If no H2s, treat whole document as one section
if (-not $h2SplitRx.IsMatch($html)) {
    $parts += @{ SeasonLabel = $null; SectionHtml = $html }
} else {
    # Split into tokens while keeping the H2 tokens
    $tokens = $h2SplitRx.Split($html)
    # tokens will include alternating non-h2, h2, non-h2, h2, ...; we want to group each h2 with following content
    $i = 0
    while ($i -lt $tokens.Length) {
        $pre = $tokens[$i]
        if ($i + 1 -lt $tokens.Length) {
            $h2 = $tokens[$i + 1]
            $nextContent = if ($i + 2 -lt $tokens.Length) { $tokens[$i + 2] } else { '' }
            # extract label text from $h2
            $label = ([regex]::Replace($h2, '(?is)<h2\b[^>]*>(?<t>.*?)</h2>', '${t}')).Trim()
            $label = [regex]::Replace($label, '<[^>]+>', '') # strip inner tags
            $parts += @{ SeasonLabel = $label; SectionHtml = $nextContent }
            $i += 3
        } else {
            # trailing HTML with no following H2
            if ($pre) { $parts += @{ SeasonLabel = $null; SectionHtml = $pre } }
            $i += 1
        }
    }
}

# Helper to extract links inside a section's HTML
function ExtractLinksFromHtml($sectionHtml, $baseUrl) {
    $found = [System.Collections.Generic.List[string]]::new()
    $attrRx = [regex]::new('(?i)\b(?:href|data-href|data-src|data-url|src)\s*=\s*(?:"(?<u>[^""<>]+)"|''(?<u>[^'']+)'')')
    foreach ($m in $attrRx.Matches($sectionHtml)) {
        $v = $m.Groups['u'].Value.Trim()
        if ($v -and $v -notmatch '^(javascript:|mailto:|#)') {
            try {
                $uri = if ([Uri]::IsWellFormedUriString($v, [UriKind]::Absolute)) { [Uri]::new($v) } else { [Uri]::new([Uri]::new($baseUrl), $v) }
                $found.Add($uri.AbsoluteUri)
            } catch { }
        }
    }
    # also grab quoted /videos/ links inside inline scripts
    $scriptUrlRx = [regex] '(?i)["''](?<u>https?://[^"'']+/videos/[^"'']+)["'']'
    foreach ($m in $scriptUrlRx.Matches($sectionHtml)) { $found.Add($m.Groups['u'].Value) }
    return $found | Sort-Object -Unique
}

# Build final list of [Url, SeasonToken] pairs by processing each part in order
$urlSeasonPairs = @()
$slug = [regex]::Escape($ShowName)
$showRx = [regex]::new("https?://[^/]+/videos/$slug(/|$)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

foreach ($part in $parts) {
    $label = $part.SeasonLabel
    $section = $part.SectionHtml
    # Determine season token from label if present
    $detected = $null
    if ($label) {
        # prefer a 4-digit year
        $ym = [regex]::Match($label, '\b(19|20)\d{2}\b')
        if ($ym.Success) { $detected = $ym.Value }
        else {
            $sm = [regex]::Match($label, '(?i)\bSeason\s+(\d{1,3})\b')
            if ($sm.Success) { $detected = $sm.Groups[1].Value }
            else { $detected = $label } # fallback to raw label
        }
    }

    $token = MakeSeasonToken $detected

    $links = ExtractLinksFromHtml $section $baseUrl
    foreach ($link in $links) {
        if ($showRx.IsMatch($link)) {
            $urlSeasonPairs += [PSCustomObject]@{ Url = $link; SeasonToken = $token }
        }
    }
}

if (-not $urlSeasonPairs -or $urlSeasonPairs.Count -eq 0) {
    Write-Warning "No episode URLs found for the show $ShowName"
    exit 0
}

# Deduplicate while preserving first-seen order (section order)
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$uniquePairs = @()
foreach ($p in $urlSeasonPairs) {
    if ($seen.Add($p.Url)) { $uniquePairs += $p }
}

# Download or list using the pair-specific season token
foreach ($p in $uniquePairs) {
    $url = $p.Url
    $seasonToken = $p.SeasonToken
    Write-Output $url

    if (-not $Download) { continue }

    # try to get episode number from yt-dlp metadata (non-blocking for progress)
    $metaJson = $null
    try {
        $procInfo = @{
            FilePath = 'yt-dlp'
            ArgumentList = @('--skip-download','--print-json',$url)
            RedirectStandardOutput = $true
            RedirectStandardError  = $false
            NoNewWindow = $true
            UseNewWindow = $false
        }
        $proc = Start-Process @procInfo -PassThru -Wait
        $stdout = $proc.StandardOutput.ReadToEnd()
        if ($stdout) { $metaJson = $stdout.Trim() }
    } catch {
        Write-Warning "Failed to retrieve metadata for the URL $url - $($_.Exception.Message)"
    }

    $meta = $null
    if ($metaJson) {
        try { $meta = $metaJson | ConvertFrom-Json } catch { $meta = $null }
    }

    $epNum = 0
    if ($meta -and $meta.episode_number -as [int]) { $epNum = [int]$meta.episode_number }
    elseif ($meta -and $meta.episode -as [int]) { $epNum = [int]$meta.episode }

    $seriesRaw = if ($meta -and $meta.series) { $meta.series } else { $ShowName }
    $seriesSafe = SafeName $seriesRaw
    if (-not $seriesSafe) { $seriesSafe = SafeName $ShowName }

    $seasonFolder = "Season $($seasonToken -replace '^S','')"
    $outDir = Join-Path $seriesSafe $seasonFolder
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null

    $epPadded = ('{0:00}' -f $epNum)
    $filenamePrefix = "$seriesSafe - $seasonToken" + "E$epPadded - %(title)s.%(ext)s"
    $outTemplate = Join-Path $outDir $filenamePrefix

    try {
        Write-Host "Starting download for $url" -ForegroundColor Cyan
        & yt-dlp -o $outTemplate $url
    } catch {
        Write-Warning "yt-dlp failed for the URL $url - $($_.Exception.Message)"
        & yt-dlp -o '%(series)s/Season %(season_number)s/%(series)s - S%(season_number)02dE%(episode_number)02d - %(title)s.%(ext)s' $url
    }
}
