import Foundation

// Tool descriptions are model-facing prose; wrapping them mid-sentence hurts
// readability of the text the LLM actually reads.
// swiftlint:disable line_length

struct ToolDefinitions {
    static let all: [[String: Any]] = [
        // find_window is deliberately NOT exposed: its Mac-coordinate JSON made
        // models reason about window positions ("off-screen at x=4639") and mix
        // coordinate systems. The 0-1000 grid + read cover every model need.
        tool("screenshot",
             description: "Take a screenshot of the iPhone screen. Returns the image directly.",
             properties: [:]),

        tool("tap",
             description: "Tap near a point on the 0-1000 grid. The tap LANDS ON THE NEAREST DETECTED ELEMENT (text or button shape) - your coordinates only select which element, so rough positions are fine. If nothing is detected nearby the tap is REFUSED (call read + tap_element instead), unless force=true for deliberately empty space. Prefer tap_text/tap_element over this.",
             properties: [
                "x": prop("number", "X on a 0-1000 grid (0=left edge, 1000=right edge)"),
                "y": prop("number", "Y on a 0-1000 grid (0=top edge, 1000=bottom edge)"),
                "force": prop("boolean", "Tap the raw point even with no element detected there (default false)"),
                "expect": prop("string", "Optional: text that should appear after the tap; verified with one automatic retry")
             ],
             required: ["x", "y"]),

        tool("run_steps",
             description: "Execute a planned sequence of actions locally in one call - USE THIS for any task needing more than 2 actions instead of acting step by step. Each step is an object with \"action\" plus that tool's parameters. Allowed actions: tap_text, type (text, submit), key, scroll, scroll_to, wait, expect (text - checkpoint that this text appears before continuing), open_app, open_url, home, back, clear_text, long_press, swipe. Steps run with automatic per-step retry; on failure you get exactly which step broke and what the screen shows, so you can re-plan. Example for a calculator: [{\"action\":\"open_app\",\"name\":\"Calculator\"},{\"action\":\"tap_text\",\"text\":\"4\"},{\"action\":\"tap_text\",\"text\":\"7\"},{\"action\":\"tap_text\",\"text\":\"\\u00d7\"},{\"action\":\"tap_text\",\"text\":\"8\"},{\"action\":\"tap_text\",\"text\":\"9\"},{\"action\":\"tap_text\",\"text\":\"=\"},{\"action\":\"expect\",\"text\":\"4,183\"}]",
             properties: [
                "steps": ["type": "array", "items": ["type": "object"],
                          "description": "Ordered step objects, each {\"action\": ..., ...params}"] as [String: Any]
             ],
             required: ["steps"]),

        tool("tap_element",
             description: "Tap an element by the [id] number from the most recent read. The most accurate single tap possible: you pick an ID, the app taps that element's measured center - no coordinates involved. Rejected if the screen changed since the read.",
             properties: [
                "id": prop("number", "The [id] from the last read output"),
                "expect": prop("string", "Optional: text that should appear after the tap; verified with one automatic retry")
             ],
             required: ["id"]),

        tool("open_url",
             description: "Open a URL or deep link on the iPhone via Spotlight. Deep links skip whole UI flows: itms-apps://itunes.apple.com/search?term=NAME jumps straight to App Store search results for NAME.",
             properties: [
                "url": prop("string", "The URL or deep link to open")
             ],
             required: ["url"]),

        tool("tap_text",
             description: "Tap an on-screen element by its visible text label (found via OCR, no coordinates). PREFER this over tap for any labeled button, tab, link, or list item, e.g. 'Search', 'Get', 'Not Now', 'Continue'. Case-insensitive.",
             properties: [
                "text": prop("string", "The visible text to tap, e.g. 'Search' or 'Not Now'"),
                "index": prop("number", "If several matches, tap the Nth from the top (default 1)"),
                "expect": prop("string", "Optional: text that should appear after the tap; verified with one automatic retry"),
                "row_button": prop("boolean", "Tap the ACTION CONTROL on that row (GET / download cloud / OPEN) instead of the label. Use this to install or open an app from a search-results list: tap_text with the app's exact title and row_button=true. Far more reliable than guessing the button's coordinates.")
             ],
             required: ["text"]),

        tool("swipe",
             description: "Swipe from (x1,y1) to (x2,y2). Coordinates are a 0-1000 grid (x: 0=left, 1000=right; y: 0=top, 1000=bottom), NOT pixels.",
             properties: [
                "x1": prop("number", "Start X, 0-1000 (0=left, 1000=right)"),
                "y1": prop("number", "Start Y, 0-1000 (0=top, 1000=bottom)"),
                "x2": prop("number", "End X, 0-1000 (0=left, 1000=right)"),
                "y2": prop("number", "End Y, 0-1000 (0=top, 1000=bottom)"),
                "duration_ms": prop("number", "Swipe duration in ms (default 300)")
             ],
             required: ["x1", "y1", "x2", "y2"]),

        tool("type_text",
             description: "Type text into the iPhone and press Return by default (required to actually run a search - typing alone leaves the query sitting in the box). Optionally tap a field first (0-1000 grid).",
             properties: [
                "text": prop("string", "Text to type"),
                "x": prop("number", "X of field to tap first, 0-1000 (0=left, 1000=right)"),
                "y": prop("number", "Y of field to tap first, 0-1000 (0=top, 1000=bottom)"),
                "submit": prop("boolean", "Press Return after typing (default true). Set false to keep typing.")
             ],
             required: ["text"]),

        tool("press_key",
             description: "Press a single key on the iPhone: return (submit a search), escape, delete, tab, space, or an arrow key.",
             properties: [
                "key": prop("string", "return | escape | delete | tab | space | left | right | up | down")
             ],
             required: ["key"]),

        tool("scroll",
             description: "Scroll the current list/page vertically with native wheel events. This is THE way to move through content - drag swipes do NOT scroll lists.",
             properties: [
                "direction": propEnum("string", "Scroll direction", ["down", "up"]),
                "amount": prop("number", "How far, 0-1000 (fraction of screen height; default 500 = half screen)")
             ],
             required: ["direction"]),

        tool("read",
             description: "Scan the screen: returns every visible text AND every unlabeled button-like shape, each with an [id]. Tap any of them with tap_element(id). The most precise way to locate targets - includes controls with no text (operator keys, download clouds, chevrons).",
             properties: [
                "filter": prop("string", "Optional regex to filter lines, e.g. 'Wi-?Fi'")
             ]),

        tool("wait",
             description: "Wait for the screen instead of taking repeated screenshots: until a text appears (condition=text), disappears (condition=gone), or animations settle (condition=still).",
             properties: [
                "condition": propEnum("string", "What to wait for", ["text", "gone", "still"]),
                "text": prop("string", "The text to wait for (required for text/gone)")
             ],
             required: ["condition"]),

        tool("long_press",
             description: "Touch and hold at a point (0-1000 grid) to open a context menu / quick actions. WARNING: long-pressing home-screen icons can enter edit (jiggle) mode - only use when a context menu is the goal. Dismiss menus by tapping empty space, never Escape.",
             properties: [
                "x": prop("number", "X on the 0-1000 grid"),
                "y": prop("number", "Y on the 0-1000 grid"),
                "duration_ms": prop("number", "Hold duration in ms (default 700)")
             ],
             required: ["x", "y"]),

        tool("back",
             description: "Navigate back one screen in the current app (taps the back control).",
             properties: [:]),

        tool("scroll_to",
             description: "Scroll until the given text is visible, optionally tapping it. Ideal for finding a row in a long list, e.g. a Settings entry.",
             properties: [
                "text": prop("string", "The text to scroll to"),
                "tap": prop("boolean", "Also tap it once visible (default false)")
             ],
             required: ["text"]),

        tool("clear_text",
             description: "Empty the focused text field (select all + delete). Use before retyping into a field that already has content.",
             properties: [:]),

        tool("double_tap",
             description: "Double-tap at a point (0-1000 grid). Mainly for zoom toggles.",
             properties: [
                "x": prop("number", "X on the 0-1000 grid"),
                "y": prop("number", "Y on the 0-1000 grid")
             ],
             required: ["x", "y"]),

        tool("open_app",
             description: "Open an app on the iPhone by name. Uses registry (fast) with Spotlight fallback. Run scan_apps first to populate the registry.",
             properties: [
                "name": prop("string", "App name to open (e.g. 'Settings', 'Safari')"),
                "method": propEnum("string", "Launch method", ["auto", "spotlight"])
             ],
             required: ["name"]),

        tool("home",
             description: "Go to the iPhone home screen via the View menu.",
             properties: [:]),

        tool("app_switcher",
             description: "Open the iPhone app switcher via the View menu.",
             properties: [:]),

        tool("status",
             description: "Check if iPhone Mirroring is connected and active.",
             properties: [:]),

        tool("scan_apps",
             description: "Scan all iPhone home screen pages via OCR and save results to persistent registry. Returns full registry JSON.",
             properties: [
                "max_pages": prop("number", "Max home screen pages to scan (default 10)")
             ]),

        tool("list_apps",
             description: "List all apps from the cached registry. Returns the saved registry data without rescanning.",
             properties: [:])
    ]

    private static func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static func propEnum(_ type: String, _ description: String, _ values: [String]) -> [String: Any] {
        ["type": type, "description": description, "enum": values]
    }

    private static func tool(_ name: String, description: String, properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "input_schema": schema
        ]
    }
}
// swiftlint:enable line_length
