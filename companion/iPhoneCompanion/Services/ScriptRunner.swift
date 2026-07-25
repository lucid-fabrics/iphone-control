import Foundation

struct ScriptResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Protocol for script execution (DIP support).
protocol ScriptRunning: Sendable {
    func run(script: String, args: [String], timeout: TimeInterval) async throws -> ScriptResult
}

extension ScriptRunning {
    func run(script: String) async throws -> ScriptResult {
        try await run(script: script, args: [], timeout: Constants.defaultScriptTimeout)
    }

    func run(script: String, args: [String]) async throws -> ScriptResult {
        try await run(script: script, args: args, timeout: Constants.defaultScriptTimeout)
    }
}

actor ScriptRunner: ScriptRunning {
    let scriptsPath: String

    init(scriptsPath: String = Constants.defaultScriptsPath) {
        self.scriptsPath = scriptsPath
    }

    func run(script: String, args: [String] = [], timeout: TimeInterval = Constants.defaultScriptTimeout) async throws -> ScriptResult {
        let scriptPath = (scriptsPath as NSString).appendingPathComponent(script)

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw ScriptError.notFound(scriptPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + args
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["PATH": Constants.scriptPATH],
            uniquingKeysWith: { _, new in new }
        )
        process.currentDirectoryURL = URL(fileURLWithPath: scriptsPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            var timedOut = false
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                timedOut = true
                process.terminate()
            }
            timer.resume()

            process.terminationHandler = { _ in
                timer.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if timedOut {
                    continuation.resume(throwing: ScriptError.timeout(timeout))
                } else if process.terminationStatus != 0 {
                    continuation.resume(throwing: ScriptError.failed(stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr))
                } else {
                    continuation.resume(returning: ScriptResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                continuation.resume(throwing: ScriptError.launchFailed(error.localizedDescription))
            }
        }
    }
}

enum ScriptError: LocalizedError {
    case notFound(String)
    case failed(String)
    case timeout(TimeInterval)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let path): return "Script not found: \(path)"
        case .failed(let msg): return msg
        case .timeout(let t): return "Script timed out after \(Int(t))s"
        case .launchFailed(let msg): return "Failed to launch: \(msg)"
        }
    }
}
