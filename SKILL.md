---
name: iphone-control
description: Control iPhone via iPhone Mirroring on macOS. Capture screenshots, tap, swipe, and type on iPhone screen rendered as a Mac window. Use when user wants to interact with their iPhone through the Mac.
---

# iPhone Mirroring Control

Control your iPhone through macOS iPhone Mirroring. The skill captures the mirroring window, analyzes it, and sends taps/swipes/typing back.

## Prerequisites

| Tool | Install | Purpose |
|------|---------|---------|
| `screencapture` | Built-in macOS | Window capture by window ID |
| `osascript` | Built-in macOS | JXA: window discovery, CGEvent taps/swipes, typing |
| `swiftc` | Xcode CLT | Auto-compiles the window/OCR helpers on first run |
| iPhone Mirroring | macOS 15+ (Sequoia) | Renders iPhone on Mac |

## Permissions Required

- **Accessibility**: Terminal/iTerm must have Accessibility access (System Settings > Privacy & Security > Accessibility)
- **Screen Recording**: Terminal/iTerm must have Screen Recording access (System Settings > Privacy & Security > Screen Recording)
- iPhone Mirroring must be open and phone connected

## Usage

All commands go through `iphone-control.sh`:

```bash
# Find the iPhone Mirroring window
./iphone-control.sh find

# Take a screenshot of the iPhone screen
./iphone-control.sh screenshot

# Tap at coordinates (relative to iPhone screen)
./iphone-control.sh tap 187 400

# Swipe (from x1,y1 to x2,y2, optional duration in ms)
./iphone-control.sh swipe 187 600 187 200
./iphone-control.sh swipe 187 600 187 200 500

# Type text (optionally tap a field first)
./iphone-control.sh type "hello world"
./iphone-control.sh type "hello world" 187 400
```

## Workflow for AI Agent

1. `find` - locate the mirroring window (do once per session)
2. `screenshot` - capture current state, analyze the image
3. Decide action based on what's visible
4. `tap`/`swipe`/`type` - execute the action
5. `screenshot` - verify the result
6. Repeat 3-5

## Coordinate System

- Origin (0,0) is the **top-left** of the iPhone Mirroring content area
- Coordinates are relative to the iPhone screen, NOT the Mac screen
- The scripts handle conversion to absolute Mac screen coordinates
- Typical iPhone screen in mirroring: ~375x812 points (varies by model)
- Screenshots are normalized to point dimensions: 1 image pixel = 1 tap coordinate
- Multi-display safe: the window can be on any display, including ones with
  negative global coordinates (left of / above primary) or a different Retina scale

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "iPhone Mirroring window not found" | Open iPhone Mirroring app on Mac |
| Tap lands in wrong spot | Run `find` again - window may have moved |
| No screen recording permission | System Settings > Privacy & Security > Screen Recording > add Terminal |
| No accessibility permission | System Settings > Privacy & Security > Accessibility > add Terminal |
