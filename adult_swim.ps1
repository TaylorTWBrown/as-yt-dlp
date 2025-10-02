param(
    [string]$ShowName
)

$baseUrl = "https://www.adultswim.com/videos/$ShowName"
$xidelCmd = "xidel `"$baseUrl`" -e `"distinct-values(//a[contains(@href, '/videos/')]/@href ! resolve-uri(., 'https://www.adultswim.com'))`""
$episodeUrls = Invoke-Expression $xidelCmd

foreach ($url in $episodeUrls) {
    yt-dlp -o "%(series)s/Season %(season_number)s/%(series)s - S%(season_number)02dE%(episode_number)02d - %(episode)s.%(ext)s" $url
}