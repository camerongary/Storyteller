# Storyteller

A macOS text-to-speech reader for writers. Open a `.txt` or `.epub` file and have it read aloud with word-by-word and sentence highlighting. Designed to work alongside [Scrivener](https://www.literatureandlatte.com/scrivener/overview) as an external editor, but works with any plain-text or epub file.

## Features

- **Word & sentence highlighting** — the current word is highlighted as it's spoken; the surrounding sentence is softly lit
- **Chapter navigation** — automatically detects chapters in `.txt` files and parses the Table of Contents from `.epub` files; skip between chapters with toolbar buttons or the ⏮/⏭ hardware media keys
- **Table of Contents sidebar** — click any chapter to jump to it instantly
- **Click to read from anywhere** — click any word in the text to start reading from that point
- **Repeated-word highlighting** — toggle to see words you've used more than once (excluding common stop words)
- **Voice picker** — choose from all English voices installed on your Mac (Premium, Enhanced, and Standard)
- **Adjustable speed** — drag the slider or press `[` / `]`; changes take effect immediately
- **Media key support** — play/pause and chapter skip work from the keyboard media keys and macOS Control Centre, even when the app is in the background
- **Open Recent** — the File menu keeps track of recently opened files
- **Light & dark mode** — respects your system appearance

## Requirements

- macOS 13 Ventura or later
- Xcode command-line tools (`xcode-select --install`)

## Building

```bash
git clone https://github.com/camerongary/Storyteller.git
cd Storyteller
bash build_app.sh
```

This compiles the app with Swift Package Manager, bundles it as `Storyteller.app`, copies it to `/Applications`, and registers it with Launch Services so it appears in Scrivener's **Compile → Open Compiled Document in** list.

## Usage

1. Launch **Storyteller** from `/Applications` (or open it directly after building)
2. Click **Open** (or use **File → Open**) to load a `.txt` or `.epub` file
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
  DocumentLoader.swift       — .txt and .epub loading, TOC parsing
  HighlightedTextView.swift  — NSTextView wrapper with click & highlight
  TOCPanel.swift             — table of contents sidebar
  HelpView.swift             — in-app help
  RecentFilesManager.swift   — recent files list (UserDefaults)
```

## License

MIT
