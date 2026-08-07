// Resident daemon mode and its client.
//
// Protocol: one request line per connection; response is zero or more data
// lines followed by "OK" or "ERR <message>". The daemon keeps the Vision OCR
// model warm and holds ONE input session open across commands, closing it
// (restoring the user's focus and cursor) after a short idle - so a burst of
// commands pays the macOS focus-steal cost once, not per action.
//
// Daemon-only verbs on top of the normal input grammar:
//   ping                      liveness check
//   read                      OCR the content area; lines "text|x|y|w|h" (native px)
//   shot <path> <norm|native> capture+crop (+resample to points for norm) to PNG
//   still <timeoutMs>         wait until the screen stops changing
//   close                     end the input session now (restore focus/cursor)
//   quit                      shut the daemon down

import CoreGraphics
import Foundation
import Vision

private let stateLock = NSLock()
private var daemonSession: Session?
private var lastCommandAt = Date()

private func ensureSessionLocked() {
    if daemonSession == nil {
        daemonSession = beginSession()
        lastPoint = daemonSession?.cursor ?? .zero
    }
}

private func closeSessionLocked() {
    if let s = daemonSession {
        daemonSession = nil
        endSession(s)
    }
}

/// Runs Vision text recognition with a reused request object (the model stays
/// loaded, which is the entire speed win over the ocr-image helper process).
private let ocrRequest: VNRecognizeTextRequest = {
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate
    r.usesLanguageCorrection = true
    return r
}()

private func ocrLines(_ img: CGImage) -> [String] {
    let handler = VNImageRequestHandler(cgImage: img, options: [:])
    guard (try? handler.perform([ocrRequest])) != nil, let results = ocrRequest.results else { return [] }
    var out: [String] = []
    for obs in results {
        // Confidence gate, matching ocr-image.swift: phone-UI scores are bimodal
        // (legit text 1.0, garbled clipped glyphs ~0.5), so <0.6 is junk.
        guard let cand = obs.topCandidates(1).first, cand.confidence >= 0.6 else { continue }
        let box = obs.boundingBox
        let px = Int(box.origin.x * Double(img.width))
        let py = Int((1.0 - box.origin.y - box.height) * Double(img.height))
        let pw = Int(box.width * Double(img.width))
        let ph = Int(box.height * Double(img.height))
        out.append("\(cand.string)|\(px)|\(py)|\(pw)|\(ph)")
    }
    return out
}

private func waitStill(timeoutMs: Double) throws -> String? {
    let win = try resolveWindow()
    let start = Date()
    let deadline = start.addingTimeInterval(timeoutMs / 1000.0)
    Thread.sleep(forTimeInterval: Tune.stillLeadIn)
    guard var prev = stillnessFrame(win) else { return nil }
    var steady = 0
    while Date() < deadline {
        Thread.sleep(forTimeInterval: Tune.stillInterval)
        guard let cur = stillnessFrame(win) else { return nil }
        if framesMatch(prev, cur) {
            steady += 1
            if steady >= Tune.stillConfirmations {
                return String(format: "%.2f", Date().timeIntervalSince(start))
            }
        } else {
            steady = 0
        }
        prev = cur
    }
    return nil
}

/// Result of one handled request.
private struct Reply {
    var data: [String] = []
    var error: String?
    var quit = false
}

private func handleRead() throws -> Reply {
    winCache = nil
    let win = try currentWin()
    guard let raw = captureWindowImage(win), let img = cropToContent(raw, win) else {
        return Reply(error: "capture failed")
    }
    return Reply(data: ocrLines(img))
}

private func handleShot(_ fields: [String]) throws -> Reply {
    guard let path = fields.first else { return Reply(error: "shot: needs <path> [norm|native]") }
    winCache = nil
    let win = try currentWin()
    guard let raw = captureWindowImage(win), var img = cropToContent(raw, win) else {
        return Reply(error: "capture failed")
    }
    if fields.count < 2 || fields[1] == "norm" {
        guard let scaled = resampleToPoints(img, win) else { return Reply(error: "resample failed") }
        img = scaled
    }
    guard writePNG(img, to: path) else { return Reply(error: "write failed: \(path)") }
    return Reply(data: [path])
}

private func handleStill(_ fields: [String]) throws -> Reply {
    let ms = fields.first.flatMap(Double.init) ?? 6000
    guard ms.isFinite, ms > 0, ms <= 120_000 else { return Reply(error: "still: bad timeout") }
    guard let elapsed = try waitStill(timeoutMs: ms) else {
        return Reply(error: "screen still changing after \(Int(ms))ms")
    }
    return Reply(data: [elapsed])
}

private func handleInputVerb(_ verb: String, _ fields: [String]) throws -> Reply {
    // Normal input grammar: needs the shared session. Window info refreshed
    // per command so a moved window never gets stale coordinates.
    winCache = nil
    _ = try currentWin()
    let act = try parseAction(verb, fields)
    ensureSessionLocked()
    run(act)
    return Reply()
}

/// Handle one request line. Recoverable errors (bad args, out-of-bounds, window
/// closed) come back as an ERR reply; the daemon keeps its warm state and the
/// next command works normally, instead of one bad input killing the process.
private func handle(_ line: String) -> Reply {
    var fields = line.split(separator: " ").map(String.init)
    guard let verb = fields.first else { return Reply(error: "empty command") }
    fields.removeFirst()
    lastCommandAt = Date()

    do {
        switch verb {
        case "ping":
            return Reply(data: ["pong"])
        case "quit":
            closeSessionLocked()
            return Reply(quit: true)
        case "close":
            closeSessionLocked()
            return Reply()
        case "bounds":
            winCache = nil
            return Reply(data: [try currentWin().json])
        case "read":
            return try handleRead()
        case "shot":
            return try handleShot(fields)
        case "still":
            return try handleStill(fields)
        default:
            return try handleInputVerb(verb, fields)
        }
    } catch let e as CommandError {
        return Reply(error: e.message)
    } catch {
        return Reply(error: "\(error)")
    }
}

private func idleWatcher() {
    while true {
        Thread.sleep(forTimeInterval: 0.25)
        stateLock.lock()
        let quiet = Date().timeIntervalSince(lastCommandAt)
        if daemonSession != nil && quiet > Tune.daemonSessionIdle {
            closeSessionLocked()
        }
        let shouldExit = quiet > Tune.daemonExitIdle
        stateLock.unlock()
        if shouldExit {
            unlink(Tune.socketPath)
            exit(0)
        }
    }
}

func runServe() -> Never {
    signal(SIGPIPE, SIG_IGN)
    signal(SIGTERM) { _ in
        unlink(Tune.socketPath)
        exit(0)
    }
    // die() inside a command must not kill the daemon session invariants
    // silently: sessions are also closed by the idle watcher, and releaseAndRestore
    // in die() handles the active one.

    unlink(Tune.socketPath)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { die("serve: socket() failed") }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        _ = Tune.socketPath.utf8CString.withUnsafeBytes { src in
            memcpy(raw.baseAddress, src.baseAddress, min(src.count, raw.count - 1))
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bound = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
    }
    guard bound == 0 else { exit(1) }   // another daemon already owns the socket
    // Owner-only: connecting to a UNIX socket requires write permission on the
    // file, and the daemon accepts full input control plus arbitrary-path reads
    // (`text`) and writes (`shot`). Without this the socket inherits the ambient
    // umask, so a permissive umask would let any local user drive the phone.
    chmod(Tune.socketPath, S_IRUSR | S_IWUSR)
    guard listen(fd, 8) == 0 else { die("serve: listen() failed") }

    Thread { idleWatcher() }.start()

    while true {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { continue }
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = recv(client, &buf, buf.count - 1, 0)
        if n > 0, let raw = String(bytes: buf[0..<n], encoding: .utf8) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            stateLock.lock()
            let result = handle(line)
            stateLock.unlock()
            var reply = result.data.joined(separator: "\n")
            if !reply.isEmpty { reply += "\n" }
            reply += result.error == nil ? "OK\n" : "ERR \(result.error ?? "")\n"
            reply.utf8CString.withUnsafeBytes { rawBytes in
                _ = send(client, rawBytes.baseAddress, rawBytes.count - 1, 0)
            }
            if result.quit {
                close(client)
                unlink(Tune.socketPath)
                exit(0)
            }
        }
        close(client)
    }
}

// MARK: - Client

private func connectToDaemon() -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        _ = Tune.socketPath.utf8CString.withUnsafeBytes { src in
            memcpy(raw.baseAddress, src.baseAddress, min(src.count, raw.count - 1))
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let ok = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
    }
    if ok == 0 { return fd }
    close(fd)
    return nil
}

/// True once the byte stream ends with "OK\n" or contains an ERR status line.
private func hasTerminator(_ bytes: [UInt8]) -> Bool {
    let ok: [UInt8] = [0x4F, 0x4B, 0x0A]                  // "OK\n"
    let err: [UInt8] = [0x0A, 0x45, 0x52, 0x52, 0x20]     // "\nERR "
    let errStart: [UInt8] = [0x45, 0x52, 0x52, 0x20]      // "ERR " at offset 0
    if bytes.count >= 3, Array(bytes.suffix(3)) == ok { return true }
    if bytes.count >= 4, Array(bytes.prefix(4)) == errStart { return true }
    guard bytes.count >= err.count else { return false }
    for i in 0...(bytes.count - err.count) where Array(bytes[i..<i + err.count]) == err {
        return true
    }
    return false
}

func runSend(_ sendArgs: [String]) -> Int32 {
    guard !sendArgs.isEmpty else {
        fputs("Error: send: needs a command\n", stderr)
        return 1
    }
    var fd = connectToDaemon()
    if fd == nil {
        // Auto-start the daemon (same binary) and retry briefly.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        proc.arguments = ["serve"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.05)
            fd = connectToDaemon()
            if fd != nil { break }
        }
    }
    guard let sock = fd else {
        fputs("Error: cannot reach or start the input daemon\n", stderr)
        return 1
    }
    defer { close(sock) }

    let line = sendArgs.joined(separator: " ") + "\n"
    let sent = line.utf8CString.withUnsafeBytes { raw in
        send(sock, raw.baseAddress, raw.count - 1, 0)
    }
    guard sent > 0 else { return 1 }

    var raw: [UInt8] = []
    var buf = [UInt8](repeating: 0, count: 65536)
    // Long verbs (drag ~9s, still up to 120s) keep the socket open silently.
    // Accumulate bytes and decode once; a multibyte character split across two
    // recv() calls would corrupt a chunk-by-chunk decode.
    while true {
        let n = recv(sock, &buf, buf.count, 0)
        if n <= 0 { break }
        raw.append(contentsOf: buf[0..<n])
        if hasTerminator(raw) { break }
    }
    let response = String(bytes: raw, encoding: .utf8) ?? ""
    var lines = response.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    while let last = lines.last, last.isEmpty { lines.removeLast() }
    guard let status = lines.last else { return 1 }
    lines.removeLast()
    for l in lines { print(l) }
    if status == "OK" { return 0 }
    fputs("Error: \(status.replacingOccurrences(of: "ERR ", with: ""))\n", stderr)
    return 1
}
