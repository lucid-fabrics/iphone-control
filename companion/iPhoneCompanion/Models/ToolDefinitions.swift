import Foundation

// Tool descriptions are model-facing prose; wrapping them mid-sentence hurts
// readability of the text the LLM actually reads.
// swiftlint:disable line_length

struct ToolDefinitions {
    static let all: [[String: Any]] = [
        tool("find_window",
             description: "Locate the iPhone Mirroring window. Returns JSON with window bounds and content bounds (iOS screen area inside bezel).",
             properties: [:]),

        tool("screenshot",
             description: "Take a screenshot of the iPhone screen. Returns the image directly.",
             properties: [:]),

        tool("tap",
             description: "Tap the iPhone screen. Coordinates are a 0-1000 grid (x: 0=left, 1000=right; y: 0=top, 1000=bottom), NOT pixels.",
             properties: [
                "x": prop("number", "X on a 0-1000 grid (0=left edge, 1000=right edge)"),
                "y": prop("number", "Y on a 0-1000 grid (0=top edge, 1000=bottom edge)")
             ],
             required: ["x", "y"]),

        tool("tap_text",
             description: "Tap an on-screen element by its visible text label (found via OCR, no coordinates). PREFER this over tap for any labeled button, tab, link, or list item, e.g. 'Search', 'Get', 'Not Now', 'Continue'. Case-insensitive.",
             properties: [
                "text": prop("string", "The visible text to tap, e.g. 'Search' or 'Not Now'"),
                "index": prop("number", "If several matches, tap the Nth from the top (default 1)"),
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
