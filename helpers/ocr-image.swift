import Vision
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: ocr-image <image-path>\n", stderr)
    exit(1)
}

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("error: cannot load image\n", stderr)
    exit(1)
}

let width = cgImage.width
let height = cgImage.height

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    fputs("error: OCR failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

guard let results = request.results else { exit(0) }

// Output: text|x|y|w|h (pixel coordinates, top-left origin)
// Confidence gate: on phone-UI content Vision scores are bimodal - legitimate
// text reads 1.0, garbled partial glyphs (half-clipped rows) read ~0.5
// ("Battery" clipped under a search pill OCR'd as "Rottor" at 0.50). Dropping
// low-confidence lines at the source keeps every consumer from trusting junk.
let minConfidence: Float = 0.6
for obs in results {
    guard let candidate = obs.topCandidates(1).first,
          candidate.confidence >= minConfidence else { continue }
    let box = obs.boundingBox
    // Convert from Vision coords (bottom-left origin, normalized) to pixel coords (top-left origin)
    let px = Int(box.origin.x * Double(width))
    let py = Int((1.0 - box.origin.y - box.height) * Double(height))
    let pw = Int(box.width * Double(width))
    let ph = Int(box.height * Double(height))
    print("\(candidate.string)|\(px)|\(py)|\(pw)|\(ph)")
}
