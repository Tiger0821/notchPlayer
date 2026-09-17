# NotchLyrics

Synced lyrics beside the MacBook notch for Apple Music — karaoke-style, with each word lighting up as it's sung.

- **Lines alternate sides:** the line being sung sits on one side of the notch and the next line waits dimmed on the other, so each new line swaps sides — left, right, left.
- **Word by word:** each word lights up as it's sung (character by character for Chinese/Japanese/Korean). Lines too long for the strip scroll to keep the sung word in view.
- **Pixel art:** words like *love*, *car* or *雨* get a little pixel picture as they're sung, and it acts the word out: cars drive off, planes take off, hearts beat. 50 are built in, and you can draw your own.
- **Automatic sync:** the app listens to Music on-device, matches the sung words to the lyrics, and corrects the timing by itself. It also compensates for Bluetooth/AirPods delay. There is no manual offset.
- **Hover to reveal:** move the pointer onto the lyrics and they fade away, showing the real menu bar. They come back when the pointer leaves.
- Shows only while Music is playing. Displays without a notch get a drawn one.
- Playback controls live in the ❝ menu bar item.

Native Swift/SwiftUI, ~1 MB, no dependencies.

## Requirements

- macOS 26 or later (built and tested on macOS 27, 14" MacBook Pro)
- Xcode (Swift 6 toolchain)
- The Apple Music app

## Build & run

```bash
./scripts/build-app.sh
open build/NotchLyrics.app
```

macOS asks for two permissions:

| Prompt | Why | If you missed it |
|---|---|---|
| Control **Music** | Read the current song and position; play/pause/skip | ❝ menu → *Allow NotchLyrics to Control Music…* |
| Record audio from other apps | Automatic sync (audio is analyzed on-device, never recorded or sent) | Settings › Sync → *Open Privacy Settings…* |
| **Accessibility** | Only if *Use Music's own lyrics* is on: reads the lyrics pane in Music | Settings › Sync → *Open Privacy Settings…* |

The app is ad-hoc signed for personal use, so macOS may ask again after a rebuild.

Run the tests:

```bash
swift test
```

## How automatic sync works

1. **Output delay:** reads the current output device's latency from Core Audio (e.g. ~170 ms for AirPods Pro) and subtracts it.
2. **Listening:** captures Music's audio with a Core Audio process tap. Apple's on-device speech recognizer (`SpeechAnalyzer`) transcribes the singing, using the song's lyrics as hints.
3. **Matching:** short recognized phrases (3 CJK characters or 2 words) vote for an offset between the lyric timestamps and playback. A repeated chorus votes for every place it occurs, with less weight, so the true offset is the densest cluster (`LyricsAligner`).
4. **Remembering:** once the estimate is stable, the offset is saved for that song and listening stops to save power. Songs not measured yet use the typical offset learned from recent songs.

The status for the current song is shown in the ❝ menu and in Settings › Sync. There, *Re-sync* forgets a song's saved timing and listens again.

## Where lyrics come from

### Music's own lyrics

Turn on **Settings › Sync → Use Music's own lyrics** to take the lyrics, and their timing, straight from
Music's lyrics pane instead of fetching them. Apple's line changes *are* the timing, so nothing has to be
lined up afterwards — auto-sync is skipped for these songs, and only the output device's delay is
compensated. It needs Accessibility permission and the lyrics view open in Music; Apple exposes no per-word
timing, so word timing inside a line is estimated. Songs Music has no lyrics for fall back to the sources
below.

### Fetched lyrics

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

## Pixel art

When a sung word has art, the art pops in right after the word, then moves the way it was drawn to:

| Motion | Built-in examples |
|---|---|
| Drive away (toward the outer edge, away from the notch) | car, bus, train, bike, boat |
| Fly away | plane, rocket, bird, butterfly, letter |
| Float up / Fall | balloon, music, ghost, angel / tears, snow |
| Heartbeat, Twinkle, Bounce, Stay | heart, star, cat, moon |

Each piece of art shows at most once per line, and at most 3 appear in one line. Matching is on whole words only: *car* also matches *cars* but not *scar* or *cares*. Apostrophes are handled (*lovin'* matches *loving*). Chinese works in Traditional or Simplified script. The longest phrase wins, so *break my heart* shows the broken heart and 飛機 shows the plane rather than the bird for 飛.

**Settings › Pixel Art** has the on/off switch, Color or White style, and a gallery of every piece. Click a piece to open the editor, or right-click to turn it off, duplicate it, export it, or reset an edited built-in.

The editor draws on a 16 × 16 grid with a pencil, eraser, fill and color picker. Colors come from the built-in retro palette or any color you pick. You can draw up to 4 animation frames, set the words that trigger the art, and choose its motion. ⌘Z undoes. Edits to built-in art can be reset to the original.

Your art, edits and turned-off pieces are saved in `~/Library/Application Support/NotchLyrics/pixel-art.json`. **Export All…** and **Import…** move art between Macs as JSON files. Importing a piece that's already in the gallery updates it instead of adding it twice.

## Settings

Open from the ❝ menu bar item. Settings has five tabs:

- **General:** live preview, show/hide, drawn notch on other displays, text size, width beside the notch
- **Lyrics:** NetEase word timing, Traditional Chinese conversion, local lyrics folder, clear cache
- **Pixel Art:** on/off, Color or White style, gallery, pixel editor, import and export
- **Sync:** where timing comes from (Music's own lyrics, automatic sync), current song status, output device delay, re-sync
- **About:** version and project link

## Notes & limitations

- Only Apple Music is supported. Spotify and browsers are not.
- Speech recognition on singing is imperfect. Heavily produced vocals, rap or languages the recognizer doesn't support may not match. Those songs fall back to the learned typical offset.
- The Simplified → Traditional conversion is character-based and can occasionally pick the wrong variant.

## Debugging

```bash
# Live logs: track changes, lyrics source, sync estimates, window frame, visibility
log stream --predicate 'subsystem == "com.tigercho.NotchLyrics"' --level info
```

Posting the distributed notification `com.tigercho.NotchLyrics.snapshot` makes the app save each overlay to `~/Library/Caches/NotchLyrics/snapshot-N.png`. With the object `settings-N` it opens Settings on tab N and saves `settings-N.png`; with `editor-ID` it opens the pixel editor for the art with that ID (like `editor-heart`) and saves `editor.png`; with `openmenu` it opens the ❝ menu briefly and saves `menu-window.png`. None of this needs Screen Recording permission.

## Project layout

```
Sources/LyricsCore/       Parsing (LRC, enhanced LRC, NetEase YRC), word-timing estimation, text matching,
                          LRCLIB/NetEase/local providers, ranking + cache, audio-to-lyrics aligner,
                          pixel art sprites, collection, word matching and editor canvas
Sources/NotchLyrics/App   App lifecycle, settings window, ❝ menu, logging
Sources/NotchLyrics/Music Music.app bridge (AppleScript) and playback clock
Sources/NotchLyrics/Notch Notch overlay window (hover to reveal) and karaoke views
Sources/NotchLyrics/PixelArt  Art library file, sprite drawing and motion, gallery, pixel editor
Sources/NotchLyrics/Sync  Output latency, Music audio tap, speech session, auto-sync controller
Tests/LyricsCoreTests/    Parser, matching, aligner and pixel art tests (Swift Testing)
scripts/build-app.sh      Builds and ad-hoc signs build/NotchLyrics.app
```
