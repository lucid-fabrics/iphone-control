# iphone-control

> Control your iPhone from the Mac terminal using iPhone Mirroring. Built for AI agents.

macOS Sequoia introduced [iPhone Mirroring](https://support.apple.com/en-us/105112) — your iPhone screen rendered as a native Mac window. **iphone-control** turns that window into a programmable interface: find it, screenshot it, tap it, swipe it, type into it. All from bash.

The killer use case? Hook it up to a multimodal AI (Claude, GPT-4V) and let the AI operate your phone.

```
┌─────────────────────────────┐
│  AI Agent (Claude, etc.)    │
│                             │
│  1. "Take a screenshot"     │
│  2. Analyzes the image      │
│  3. "Tap Settings at 187,400│
│  4. "Take another screenshot│
│  5. Verifies result         │
│  6. Repeat                  │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  iphone-control             │
│                             │
│  screenshot → tap → swipe   │
│  → type → screenshot → ...  │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│  iPhone Mirroring (macOS)   │
│  ┌───────────────────┐      │
│  │                   │      │
│  │   Your iPhone     │      │
│  │   screen here     │      │
│  │                   │      │
│  └───────────────────┘      │
└─────────────────────────────┘
```

## Requirements

- **macOS 15** (Sequoia) or later
- **iPhone Mirroring** open and connected
- [`cliclick`](https://github.com/BlueM/cliclick) — `brew install cliclick`
- **Terminal permissions**: Accessibility + Screen Recording (System Settings → Privacy & Security)

## Install

```bash
git clone https://github.com/wmehanna/iphone-control.git
cd iphone-control
brew install cliclick
```

## Usage

```bash
# Locate the iPhone Mirroring window
./iphone-control.sh find
# → {"id": 1234, "x": 100, "y": 200, "width": 393, "height": 852}

# Capture a screenshot
./iphone-control.sh screenshot
# → /tmp/iphone-screen.png

# Tap at a point (coordinates relative to iPhone screen)
./iphone-control.sh tap 187 400

# Swipe up (scroll down)
./iphone-control.sh swipe 187 600 187 200

# Swipe slowly (custom duration in ms)
./iphone-control.sh swipe 187 600 187 200 800

# Type text
./iphone-control.sh type "hello world"

# Tap a text field, then type into it
./iphone-control.sh type "hello world" 187 400
```

## Commands

| Command | Args | Description |
|---------|------|-------------|
| `find` | — | Returns window position + size as JSON |
| `screenshot` | `[output_path]` | Saves iPhone screen to PNG (default: `/tmp/iphone-screen.png`) |
| `tap` | `<x> <y>` | Tap at coordinates |
| `swipe` | `<x1> <y1> <x2> <y2> [ms]` | Swipe between two points |
| `type` | `"text" [x y]` | Type text, optionally into a tapped field |

## Coordinates

All coordinates are **relative to the iPhone screen**, not the Mac desktop.

- `(0, 0)` = top-left corner of the iPhone Mirroring content
- Scripts automatically convert to absolute Mac screen position
- Run `find` to see the window dimensions for your device

## AI Agent Integration

The scripts are designed to be called by an AI agent in a loop:

```bash
# Agent workflow
./iphone-control.sh screenshot              # 1. Capture state
# → AI sees the screenshot and decides...
./iphone-control.sh tap 187 400             # 2. Execute action
./iphone-control.sh screenshot              # 3. Verify result
# → AI checks if action succeeded, plans next step
```

Works with any tool-using AI that supports image input. The `find` result is cached for 30 seconds, so rapid screenshot→tap→screenshot cycles are fast.

## Permissions Setup

Your terminal app needs two permissions. macOS will prompt on first use, or set them manually:

1. **System Settings → Privacy & Security → Accessibility** → toggle on your terminal
2. **System Settings → Privacy & Security → Screen Recording** → toggle on your terminal

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `iPhone Mirroring window not found` | Open the iPhone Mirroring app on your Mac |
| `cliclick not found` | `brew install cliclick` |
| Taps land in the wrong spot | Run `find` to refresh window position (it may have moved) |
| Screenshot is blank or fails | Grant Screen Recording permission to your terminal |
| Clicks don't register | Grant Accessibility permission to your terminal |
| Window found but actions don't work | Make sure iPhone Mirroring is in the foreground |

## How It Works

| Script | Mechanism |
|--------|-----------|
| `find-window.sh` | JXA + `CGWindowListCopyWindowInfo` to find the "iPhone Mirroring" window |
| `screenshot.sh` | `screencapture -R x,y,w,h` to capture just that region |
| `tap.sh` | Translates relative→absolute coords, then `cliclick c:X,Y` |
| `swipe.sh` | `cliclick dd:` → 10 interpolated `m:` moves → `du:` for smooth gesture |
| `type-text.sh` | Optional `tap.sh` call, then `cliclick t:"text"` |

## License

MIT
