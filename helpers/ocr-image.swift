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

// Output: text|x|y|w|h (normalized 0-1 coordinates, origin bottom-left)
for obs in results {
    guard let candidate = obs.topCandidates(1).first else { continue }
    let box = obs.boundingBox
    // Convert from Vision coords (bottom-left origin, normalized) to pixel coords (top-left origin)
    let px = Int(box.origin.x * Double(width))
    let py = Int((1.0 - box.origin.y - box.height) * Double(height))
    let pw = Int(box.width * Double(width))
    let ph = Int(box.height * Double(height))
    print("\(candidate.string)|\(px)|\(py)|\(pw)|\(ph)")
}
