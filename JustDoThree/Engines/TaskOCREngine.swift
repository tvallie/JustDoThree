import Vision
import UIKit

struct TaskOCREngine {
    static func recognizeLines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Vision bounding boxes use bottom-left origin, so higher minY = higher on screen
                let lines = observations
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 1 }

                continuation.resume(returning: lines)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
