//
//  LabelReader.swift
//  My Cocktail Collection
//
//  Label scanning, step 2: reads the text on a label photo with Apple's Vision framework, on the phone.
//  The lines it returns go to LabelMatcher, which works out the brand, type and notes.
//

import UIKit
import Vision

enum LabelReader {
    /// Reads every line of text on the photo, with its size and position. Runs off the main thread.
    /// Returns no lines when nothing could be read.
    static func read(_ image: UIImage) async throws -> [LabelLine] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                // Brand names aren't dictionary words, so don't "correct" them.
                request.usesLanguageCorrection = false
                request.automaticallyDetectsLanguage = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handler.perform([request])
                    continuation.resume(returning: lines(from: request.results ?? []))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Vision's boxes are 0–1 with the origin at the bottom left; LabelLine measures from the top.
    static func lines(from observations: [VNRecognizedTextObservation]) -> [LabelLine] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            let box = observation.boundingBox
            return LabelLine(candidate.string, height: Double(box.height), top: Double(1 - box.maxY))
        }
    }
}

extension CGImagePropertyOrientation {
    /// The matching orientation for a photo, so text on a sideways photo is read the right way up.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
