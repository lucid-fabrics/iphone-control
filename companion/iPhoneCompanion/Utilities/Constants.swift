import Foundation

enum Constants {
    static let defaultScriptsPath: String = {
        // Try to detect from app bundle location (companion/ is inside iphone-control/)
        let bundlePath = Bundle.main.bundlePath
        let companionDir = (bundlePath as NSString).deletingLastPathComponent
        let parentDir = (companionDir as NSString).deletingLastPathComponent

        // Check if parent has iphone-control.sh
        let marker = (parentDir as NSString).appendingPathComponent("iphone-control.sh")
        if FileManager.default.fileExists(atPath: marker) {
            return parentDir
        }

        // Fallback: check common locations
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/git/iphone-control",
            "\(home)/Developer/iphone-control",
            "\(home)/Projects/iphone-control",
        ]
        for path in candidates {
            let check = (path as NSString).appendingPathComponent("iphone-control.sh")
            if FileManager.default.fileExists(atPath: check) {
                return path
            }
        }

        return "\(home)/git/iphone-control"
    }()

    static let scriptPATH = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ].joined(separator: ":")

    // MARK: - API URLs

    static let claudeAPIURL = "https://api.anthropic.com/v1/messages"
    static let claudeModelsURL = "https://api.anthropic.com/v1/models"
    static let openRouterAPIURL = "https://openrouter.ai/api/v1/chat/completions"
    static let openRouterModelsURL = "https://openrouter.ai/api/v1/models"
    static let minimaxAPIURL = "https://api.minimax.io/v1/chat/completions"

    // MARK: - Default Models

    static let defaultClaudeModel = "claude-sonnet-4-6-20250514"
    static let defaultOpenRouterModel = "anthropic/claude-sonnet-4.6"
    static let defaultOpenRouterVisionModel = "google/gemma-3-12b-it:free"
    static let defaultOllamaURL = "http://localhost:11434"
    static let defaultOllamaModel = "llama3.1"
    static let defaultMiniMaxModel = "MiniMax-M2.7"

    // MARK: - AI Request Parameters

    static let maxTokens = 4096
    static let visionMaxTokens = 1024

    // MARK: - Tool Loop Limits

    static let maxToolIterations = 20

    // MARK: - Timing Constants (Input Controller)

    static let tapDownUpDelay: TimeInterval = 0.02
    static let activateDelay: TimeInterval = 0.05
    static let tapSettleDelay: UInt64 = 600_000_000        // 600ms — let iOS animation settle after tap
    static let swipeSettleDelay: UInt64 = 500_000_000      // 500ms — let iOS settle after swipe
    static let keystrokeDelay: TimeInterval = 0.005
    static let menuOpenDelay: TimeInterval = 0.1
    static let spotlightOpenDelay: UInt64 = 400_000_000  // nanoseconds
    static let spotlightSearchDelay: UInt64 = 1_000_000_000  // nanoseconds

    // MARK: - App Identifiers

    static let iphoneMirroringBundleId = "com.apple.ScreenContinuity"

    // MARK: - Open App Constants

    static let homeScreenDelay: UInt64 = 500_000_000       // nanoseconds
    static let pageSwipeDelay: UInt64 = 300_000_000        // nanoseconds
    static let swipeEdgeMargin = 30
    static let defaultSwipeDuration = 300                  // milliseconds

    // MARK: - Script Timeouts

    static let defaultScriptTimeout: TimeInterval = 15
    static let scanTimeout: TimeInterval = 120

    // MARK: - OAuth

    static let oauthClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let oauthTokenURL = "https://console.anthropic.com/v1/oauth/token"

    // MARK: - System Prompt

    static let systemPrompt = """
        You control an iPhone through iPhone Mirroring on macOS. You have tools to tap, swipe, type, take screenshots, open apps, and navigate.

        Coordinates are relative to the iPhone content area (top-left = 0,0).

        ## MANDATORY VERIFICATION LOOP — follow for EVERY action:
        1. take_screenshot → analyze what's on screen
        2. decide on ONE action
        3. execute that action
        4. take_screenshot → confirm the result before proceeding
        5. If the result is unexpected, STOP and re-assess — never blindly continue

        ## OVERLAY HANDLING:
        After any navigation or app launch, always check for and dismiss prompts ("Not Now", "Skip", "Later", "Allow", "Don't Allow", "Continue", "OK"). Tap them before proceeding. Failure to dismiss overlays will cause all subsequent taps to miss their targets.

        ## COORDINATE ACCURACY:
        - Tap exactly on the center of interactive elements — buttons, icons, input fields
        - If a tap doesn't produce the expected result, do NOT retry in the same spot; re-evaluate coordinates from a fresh screenshot
        - Swipe slowly and deliberately; verify the swipe worked before the next action

        ## RESPONSE STYLE:
        - Describe what you SEE on screen after each screenshot, then what you're doing next
        - Never repeat raw tool output (e.g., don't say "Tapped at (187, 400)")
        - Be concise — one sentence per action is enough
        - If you're stuck or something unexpected happens, say so clearly

        ## SPEED:
        - Never chain multiple actions without a verification screenshot between them
        - Quality over speed — one correct action is better than three wrong ones
        """

    // Fallback static list if API fetch fails
    static let fallbackClaudeModels: [(id: String, name: String)] = [
        ("claude-opus-4-6-20250514", "Opus 4.6"),
        ("claude-sonnet-4-6-20250514", "Sonnet 4.6"),
        ("claude-sonnet-4-5-20250514", "Sonnet 4.5"),
        ("claude-haiku-4-5-20251001", "Haiku 4.5"),
    ]

    static let fallbackOpenRouterModels: [(id: String, name: String)] = [
        ("anthropic/claude-opus-4.6", "Claude Opus 4.6"),
        ("anthropic/claude-sonnet-4.6", "Claude Sonnet 4.6"),
        ("anthropic/claude-haiku-4.5", "Claude Haiku 4.5"),
        ("google/gemini-2.5-pro-preview", "Gemini 2.5 Pro"),
        ("openai/gpt-4o", "GPT-4o"),
    ]

    static let fallbackMiniMaxModels: [(id: String, name: String)] = [
        ("MiniMax-M2.7", "MiniMax M2.7"),
        ("MiniMax-M2.7-highspeed", "MiniMax M2.7 Highspeed"),
        ("MiniMax-M2.5", "MiniMax M2.5"),
        ("MiniMax-M2.5-highspeed", "MiniMax M2.5 Highspeed"),
        ("M2-her", "MiniMax M2-Her (Roleplay)"),
        ("MiniMax-Text-01", "MiniMax Text 01 (Legacy)"),
    ]
}
