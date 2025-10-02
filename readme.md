Adult Swim YTDLP helper Script
# Adult Swim YTDLP helper script

Extract absolute episode URLs from an Adult Swim show listing page (for example: https://www.adultswim.com/videos/assy-mc-gee/irish-wake) so you can pipe them into a downloader such as `yt-dlp`.

## Purpose

This small PowerShell helper extracts absolute episode links from an Adult Swim show's listing page (the show "slug"), printing one URL per line. It's designed to be piped into `yt-dlp` or another downloader.

## Requirements

- Windows PowerShell (or PowerShell Core)
- `yt-dlp` — only needed if you plan to download videos

### Install yt-dlp (Windows)

Run in an elevated PowerShell prompt:

```powershell
winget install -e --id yt-dlp.yt-dlp
```

## Installation

Save the PowerShell script in this repository (for example: `extract-episodes.ps1`).

## Usage

Run the script, passing the show slug with the `-ShowName` parameter. Example:

```powershell
.\extract-episodes.ps1 -ShowName 'assy-mc-gee'
```

To download each episode with `yt-dlp`, pipe the output:

```powershell
.\extract-episodes.ps1 -ShowName 'assy-mc-gee' -Download
```

The script prints one absolute episode URL per line to stdout, suitable for piping or saving to a file.

## Notes

- No external HTML parsers are required — the script uses built-in PowerShell/.NET APIs.
- Provide the show slug (the part used in Adult Swim URLs). For example, the slug for "Assy McGee" is `assy-mc-gee`.

## Example output

```
https://www.adultswim.com/videos/assy-mc-gee/irish-wake
https://www.adultswim.com/videos/assy-mc-gee/murder-by-the-docks
```

## Thanks

Thanks to ohmybahgosh/YT-DLP-SCRIPTS for inspiration.

## Contributing

Feel free to open issues or pull requests to improve the script or README. Add tests or Windows/PowerShell compatibility fixes as needed.