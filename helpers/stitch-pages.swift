// Stitch several overlapping `read.sh --json` pages of one scrolling list into a
// single de-duplicated, top-to-bottom list.
//
// Input (stdin): one JSON array per line, one line per page, in scroll order.
// Each array holds read.sh objects: {"text","x","y","w","h","cx","cy"}.
//
// Usage: stitch-pages [--json|--count|--offset] [--step N] [--grep REGEX]
//   (default)  aligned text, one row per line: "y_abs  text", chrome as "fixed"
//   --json     JSON array of {text, x, y_abs, page, fixed[, seam_uncertain]}
//   --count    number of content rows (read-all.sh uses it to detect the bottom)
//   --offset   total measured scroll offset in points (used to scroll back)
//   --step N   fallback offset for a page that shares no text with the previous
//   --grep R   keep only rows whose text matches R (case-insensitive)
//
// Why measure: line-unit wheel scrolling does not move an exact number of
// points, so the page offset is taken from text seen on both pages, never
// computed from the requested scroll distance.

import Foundation

struct Item: Decodable {
    let text: String
    let cx: Int
    let cy: Int
}

struct Row {
    let text: String
    let norm: String
    let x: Int
    let screenY: Int
    let yAbs: Int
    let page: Int
    let seamUncertain: Bool
}

/// Text that moved by at most this much between pages did not scroll: it is
/// fixed chrome (status bar, nav bar title, tab bar).
let fixedTolerance = 3
/// Same text within this many points of an existing row is the same row.
let dedupeTolerance = 8

var mode = "text"
var step = 0
var grepPattern: NSRegularExpression?
var argIndex = 1
let argv = CommandLine.arguments
while argIndex < argv.count {
    switch argv[argIndex] {
    case "--json": mode = "json"
    case "--count": mode = "count"
    case "--offset": mode = "offset"
    case "--step":
        argIndex += 1
        guard argIndex < argv.count, let value = Int(argv[argIndex]), value > 0 else {
            fputs("error: --step needs a positive integer\n", stderr)
            exit(1)
        }
        step = value
    case "--grep":
        argIndex += 1
        guard argIndex < argv.count,
              let regex = try? NSRegularExpression(pattern: argv[argIndex], options: [.caseInsensitive])
        else {
            fputs("error: --grep needs a valid regex\n", stderr)
            exit(1)
        }
        grepPattern = regex
    default:
        fputs("error: unknown option: \(argv[argIndex])\n", stderr)
        exit(1)
    }
    argIndex += 1
}

/// Fold typographic punctuation to ASCII and lowercase, same rule as
/// tap-text.sh, so "Don't" and "Don\u{2019}t" are one row.
func normalize(_ text: String) -> String {
    var out = text.trimmingCharacters(in: .whitespaces)
    for (from, to) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{02BC}", "'"),
                       ("\u{201C}", "\""), ("\u{201D}", "\""),
                       ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{2026}", "...")] {
        out = out.replacingOccurrences(of: from, with: to)
    }
    return out.lowercased()
}

/// Synthetic shape entries renumber on every page, so they cannot be stitched.
func isShape(_ text: String) -> Bool {
    text.range(of: #"^\(button \d+\)$"#, options: .regularExpression) != nil
}

func median(_ values: [Int]) -> Int {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

// Read pages.
var pages: [[Item]] = []
while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    guard let data = trimmed.data(using: .utf8),
          let items = try? JSONDecoder().decode([Item].self, from: data) else {
        fputs("error: page \(pages.count) is not a read.sh --json array\n", stderr)
        exit(1)
    }
    pages.append(items.filter { !isShape($0.text) && !normalize($0.text).isEmpty })
}

var rows: [Row] = []
var chrome: [(norm: String, screenY: Int)] = []
var cumulative = 0

func isDuplicate(_ norm: String, _ yAbs: Int) -> Bool {
    rows.contains { $0.norm == norm && abs($0.yAbs - yAbs) <= dedupeTolerance }
}

for (pageIndex, items) in pages.enumerated() {
    var offset = 0
    var uncertain = false
    var fixedHere = Set<Int>()

    if pageIndex > 0 {
        let previous = pages[pageIndex - 1]
        // Anchor on texts that appear exactly once on each page; repeated
        // labels ("On", "Off", ">") pair up wrongly and skew the offset.
        func counts(_ list: [Item]) -> [String: Int] {
            list.reduce(into: [:]) { $0[normalize($1.text), default: 0] += 1 }
        }
        let prevCounts = counts(previous)
        let curCounts = counts(items)
        var moved: [Int] = []
        var stillCount = 0
        for (i, item) in items.enumerated() {
            let norm = normalize(item.text)
            guard curCounts[norm] == 1, prevCounts[norm] == 1,
                  let match = previous.first(where: { normalize($0.text) == norm }) else { continue }
            let delta = match.cy - item.cy
            if abs(delta) <= fixedTolerance {
                stillCount += 1
                fixedHere.insert(i)
            } else if delta > 0 {
                moved.append(delta)
            }
        }
        if !moved.isEmpty {
            offset = median(moved)
        } else if stillCount > 0 {
            // Nothing scrolled: the list was already at its bottom.
            offset = 0
            fixedHere.removeAll()
        } else {
            offset = step
            uncertain = true
        }
        // Only chrome when the content around it actually moved.
        if offset > 0 {
            for i in fixedHere {
                chrome.append((normalize(items[i].text), items[i].cy))
            }
        } else {
            fixedHere.removeAll()
        }
    }
    cumulative += offset

    for (i, item) in items.enumerated() where !fixedHere.contains(i) {
        let norm = normalize(item.text)
        // Chrome found on an earlier page stays chrome on every later page,
        // including pages that did not scroll (where it cannot be re-detected).
        if pageIndex > 0, chrome.contains(where: {
            $0.norm == norm && abs($0.screenY - item.cy) <= fixedTolerance
        }) { continue }
        let yAbs = cumulative + item.cy
        if isDuplicate(norm, yAbs) { continue }
        rows.append(Row(text: item.text, norm: norm, x: item.cx, screenY: item.cy,
                        yAbs: yAbs, page: pageIndex, seamUncertain: uncertain))
    }
}

func isChrome(_ row: Row) -> Bool {
    row.page == 0 && chrome.contains { $0.norm == row.norm && abs($0.screenY - row.screenY) <= fixedTolerance }
}

let fixedRows = rows.filter(isChrome)
let contentRows = rows.filter { !isChrome($0) }
    .sorted { ($0.yAbs, $0.x) < ($1.yAbs, $1.x) }

func matchesGrep(_ row: Row) -> Bool {
    guard let regex = grepPattern else { return true }
    let range = NSRange(row.text.startIndex..., in: row.text)
    return regex.firstMatch(in: row.text, range: range) != nil
}

func jsonEscape(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out
}

switch mode {
case "count":
    print(contentRows.count)
case "offset":
    print(cumulative)
case "json":
    let all = fixedRows.map { ($0, true) } + contentRows.map { ($0, false) }
    let objects = all.filter { matchesGrep($0.0) }.map { row, fixed -> String in
        var obj = "{\"text\":\"\(jsonEscape(row.text))\",\"x\":\(row.x),\"y_abs\":\(row.yAbs)"
        obj += ",\"page\":\(row.page),\"fixed\":\(fixed)"
        if row.seamUncertain { obj += ",\"seam_uncertain\":true" }
        return obj + "}"
    }
    print("[" + objects.joined(separator: ",") + "]")
default:
    func pad(_ value: String) -> String {
        String(repeating: " ", count: max(0, 6 - value.count)) + value
    }
    for row in fixedRows where matchesGrep(row) {
        print("\(pad("fixed"))  \(row.text)")
    }
    for row in contentRows where matchesGrep(row) {
        let mark = row.seamUncertain ? " (seam uncertain)" : ""
        print("\(pad(String(row.yAbs)))  \(row.text)\(mark)")
    }
}
