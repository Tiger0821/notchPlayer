# NotchLyrics

Synced lyrics beside the MacBook notch for Apple Music — karaoke-style, with each word lighting up as it's sung.

- **Left of the notch:** the current line, filling word by word (character by character for Chinese/Japanese/Korean).
- **Right of the notch:** the next line, dimmed.
- **Click the bar:** a panel drops down with artwork, previous / play-pause / next, progress, and a quick lyric-timing nudge.
- Shows only while Music is playing, so the normal menu bar comes back when you pause.
- Displays without a notch get a drawn one.

Native Swift/SwiftUI, ~1 MB, no dependencies.

## Requirements

- macOS 14 or later (built and tested on macOS 27, 14" MacBook Pro)
- Xcode or the Xcode Command Line Tools (Swift 5.10+)
- The Apple Music app

## Build & run

```bash
./scripts/build-app.sh
open build/NotchLyrics.app
```

On first launch macOS asks to let NotchLyrics control **Music** — click **Allow**. If you missed it: menu bar ❝ icon → *Allow NotchLyrics to Control Music…* (or System Settings › Privacy & Security › Automation).

The app is ad-hoc signed for personal use, so macOS may ask for that permission again after a rebuild.

Run the tests:

```bash
swift test
```

## Where lyrics come from

Sources are ranked by quality; the best available wins:

| Rank | Source | Timing |
|---|---|---|
| 1 | Local `.lrc` file with word tags (enhanced LRC) | per word |
| 2 | [NetEase Cloud Music](https://music.163.com) YRC | per word |
| 3 | Local `.lrc` file | per line |
| 4 | [LRCLIB](https://lrclib.net) | per line |
| 5 | NetEase LRC | per line |
| — | nothing found | shows title — artist |

With line-only timing, word timing is estimated from the line length.

Online matches must be within ±3 s of the track's length, which filters out covers and remixes. Results are cached in `~/Library/Caches/NotchLyrics/`.

> NetEase is an unofficial API and may break or lack some artists. It can be turned off in Settings.

### Local lyrics

Drop `.lrc` files into `~/Music/NotchLyrics/` (subfolders are fine), named either:

```
Artist - Title.lrc
Title.lrc
```

Matching ignores case, punctuation, Traditional/Simplified script and suffixes like "(Remastered)".

Enhanced LRC word tags are supported:

```
[00:10.00]<00:10.00>Walking <00:10.50>on <00:11.00>clouds<00:12.00>
```

## Settings

Open from the ❝ menu bar icon, or the gear in the drop-down panel:

- Show/hide lyrics, and draw a notch on external displays
- Font size, and width of the strips beside the notch
- **Lyrics timing** offset (positive = lyrics earlier)
- Use NetEase word-level lyrics
- Convert Simplified Chinese to Traditional (skipped for Japanese lyrics)

## Notes & limitations

- While music plays, the strips beside the notch cover the menu bar items underneath (including the ❝ icon). Use the gear in the drop-down panel, pause, or narrow the strips in Settings.
- Only Apple Music is supported. Spotify and browsers are not.
- The Simplified → Traditional conversion is character-based and can occasionally pick the wrong variant.

## Debugging

```bash
# Live logs: track changes, lyrics source, window frame, visibility
log stream --predicate 'subsystem == "com.tigercho.NotchLyrics"' --level info
```

Posting the distributed notification `com.tigercho.NotchLyrics.snapshot` makes the app save each overlay to `~/Library/Caches/NotchLyrics/snapshot-N.png`. This needs no Screen Recording permission.

## Project layout

```
Sources/LyricsCore/     Parsing (LRC, enhanced LRC, NetEase YRC), word-timing estimation,
                        text matching, LRCLIB/NetEase/local providers, ranking + cache
Sources/NotchLyrics/    App: Music.app bridge (AppleScript), notch overlay window,
                        karaoke views, controls panel, menu bar item, settings
Tests/LyricsCoreTests/  Parser and matching tests (Swift Testing)
scripts/build-app.sh    Builds and ad-hoc signs build/NotchLyrics.app
```
