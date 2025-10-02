param(
    [Parameter(Mandatory = $true)]
    [string]$ShowName,

    [switch]$Download
)

Set-StrictMode -Version Latest

$baseUrl = "https://www.adultswim.com/videos/$ShowName"
$baseUri = [Uri]::new($baseUrl)
$userAgent = 'Mozilla/5.0 (Windows NT)'

try {
    $resp = Invoke-WebRequest -Uri $baseUrl -Headers @{ 'User-Agent' = $userAgent } -ErrorAction Stop
} catch {
    Write-Error "Failed to fetch $baseUrl $($_.Exception.Message)"
    exit 1
}

$html = $resp.Content

# Collect candidate URL attributes commonly used by pages and JS-rendered UIs
$attrPatterns = @(
    'href',
    'data-href',
    'data-src',
    'data-url',
    'src'
)

$attrRegexFormat = '(?i){0}\s*=\s*(?:"(?<u>[^"<>]+)"|''(?<u>[^'']+)'')'
$found = [System.Collections.Generic.List[string]]::new()

foreach ($attr in $attrPatterns) {
    $regex = [regex]::new([string]::Format($attrRegexFormat, [regex]::Escape($attr)), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($m in $regex.Matches($html)) {
        $val = $m.Groups['u'].Value.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) { continue }
        if ($val -match '^(javascript:|mailto:|#)') { continue }
        try {
            $absUri = if ([Uri]::IsWellFormedUriString($val, [UriKind]::Absolute)) {
                [Uri]::new($val)
            } else {
                [Uri]::new($baseUri, $val)
            }
        } catch {
            continue
        }
        $found.Add($absUri.AbsoluteUri)
    }
}

# Extract quoted /videos/ links from inline scripts or JSON
$scriptUrlRegex = [regex] '(?i)["''](?<u>https?://[^"'']+/videos/[^"'']+)["'']'
foreach ($m in $scriptUrlRegex.Matches($html)) {
    $found.Add($m.Groups['u'].Value)
}

# Normalize, filter only links under this show's path, dedupe, and sort
$escapedSlug = [regex]::Escape($ShowName)
$showPathRegex = [regex]::new("https?://[^/]+/videos/$escapedSlug(/|$)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$episodeUrls = $found |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and $showPathRegex.IsMatch($_) } |
    Sort-Object -Unique

if (-not $episodeUrls -or $episodeUrls.Count -eq 0) {
    Write-Warning "No episode URLs found for show: $ShowName"
    exit 0
}

# Output each URL and optionally download with yt-dlp
foreach ($u in $episodeUrls) {
    Write-Output $u
    if ($Download) {
        try {
            & yt-dlp -o '%(series)s/Season %(season_number)s/%(series)s - S%(season_number)02dE%(episode_number)02d - %(episode)s.%(ext)s' $u
        } catch {
            Write-Warning "yt-dlp failed for $u $($_.Exception.Message)"
        }
    }
}
