# Storyteller

A macOS text-to-speech reader for writers. Open a `.txt`, `.rtf`, `.epub`, or `.pdf` file and have it read aloud with word-by-word and sentence highlighting. Designed to work alongside [Scrivener](https://www.literatureandlatte.com/scrivener/overview) as an external editor, but works with any supported file.

## Features

- **Word & sentence highlighting** — the current word is highlighted as it's spoken; the surrounding sentence is softly lit
- **Notes & revisions** — select text (or just listen) and add comments or suggested revisions; annotated passages get a dotted underline, notes persist per document, and everything exports to Markdown for your revision pass
- **Chapter navigation** — automatically detects chapters in `.txt` files, parses the Table of Contents from `.epub` files, and uses the bookmarks outline from `.pdf` files; skip between chapters with toolbar buttons or the ⏮/⏭ hardware media keys
- **Table of Contents sidebar** — click any chapter to jump to it instantly
- **Click to read from anywhere** — click any word in the text to start reading from that point
- **PDF support** — open any text-based PDF; bookmarked PDFs show a full chapter sidebar
- **Multi-language voices** — choose from all languages installed on your Mac, grouped by language in the voice picker
- **Repeated-word highlighting** — toggle to see words you've used more than once (excluding common stop words)
- **Voice picker** — choose from all voices installed on your Mac (Premium, Enhanced, and Standard), grouped by language
- **Adjustable speed** — drag the slider or press `[` / `]`; changes take effect immediately
- **Media key support** — play/pause and chapter skip work from the keyboard media keys and macOS Control Centre, even when the app is in the background
- **Double-click toolbar to zoom** — double-click anywhere in the toolbar to expand or minimise the window (respects your system preference)
- **Open Recent** — the File menu keeps track of recently opened files
- **Light & dark mode** — respects your system appearance

## Download

Grab the latest DMG from the [Releases](https://github.com/camerongary/Storyteller/releases) page, open it, and drag **Storyteller** to your Applications folder.

> **First launch:** macOS will ask you to confirm opening an app from an unidentified developer. Right-click the app → **Open** → **Open** in the dialog. This is a one-time step.

## Requirements

- macOS 13 Ventura or later

## Building from source

```bash
git clone https://github.com/camerongary/Storyteller.git
cd Storyteller
bash build_app.sh
```

This compiles the app with Swift Package Manager, bundles it as `Storyteller.app`, copies it to `/Applications`, and registers it with Launch Services so it appears in Scrivener's **Compile → Open Compiled Document in** list.

Requires Xcode command-line tools (`xcode-select --install`).

## Usage

1. Launch **Storyteller** from `/Applications` (or open it directly after building)
2. Click **Open** (or use **File → Open**) to load a `.txt`, `.epub`, or `.pdf` file
3. Press **Space** or click ▶︎ to start reading
4. Click any word to jump to that position and begin reading from there
5. Use the ⏮ / ⏭ buttons (or hardware media keys) to move between chapters

### Keyboard shortcuts

| Key | Action |
|-----|--------|
| Space | Play / Pause |
| `[` | Slower |
| `]` | Faster |
| ⌘← | Previous chapter (or sentence) |
| ⌘→ | Next chapter (or sentence) |

### Scrivener integration

In Scrivener, go to **File → Compile**, expand the **Share** section, and set **Open compiled document in** to **Storyteller**. After compiling, Scrivener will open the exported file directly in Storyteller.

## Project structure

```
Sources/ScrivenerReader/
  ScrivenerReaderApp.swift   — app entry point, menu, help window
  ContentView.swift          — main UI, toolbar, status bar
  SpeechManager.swift        — TTS engine, media key registration
  TextProcessor.swift        — word/sentence tokenisation, repeat detection
  DocumentLoader.swift       — .txt, .epub, and .pdf loading, TOC parsing
  HighlightedTextView.swift  — NSTextView wrapper with click & highlight
  TOCPanel.swift             — table of contents sidebar
  HelpView.swift             — in-app help
  RecentFilesManager.swift   — recent files list (UserDefaults)
```

## License

MIT
