//
//  ImageProcessor.swift
//  THERMOAI — Services
//
//  Purpose: Prepares meal photos for upload (downscale + JPEG, strips metadata by
//           re-encoding) and runs an on-device Vision pre-check so obviously
//           non-food photos never consume AI quota.
//  Dependencies: UIKit, Vision, CoreML (via Vision's built-in classifier)
//
//  Core ML note: Vision's `ClassifyImageRequest` runs Apple's built-in Core ML
//  image classifier on the Neural Engine. A custom food model (.mlmodel) can be
//  dropped in later via `CoreMLRequest` without changing callers.
//

import UIKit
import Vision

enum ImageProcessor {
    /// Longest edge sent to the backend. 1024 px balances accuracy and payload size.
    static let maxDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.72

    enum ImageError: Error, LocalizedError {
        case encodingFailed
        var errorDescription: String? { "Couldn't prepare that photo. Please try another." }
    }

    /// Downscales and re-encodes as JPEG (removing EXIF/GPS metadata).
    static func preparedJPEG(from image: UIImage) throws -> Data {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { throw ImageError.encodingFailed }
        return data
    }

    // MARK: Vision pre-check

    /// Identifiers from Vision's taxonomy that indicate food or drink.
    private static let foodKeywords: [String] = [
        "food", "meal", "dish", "fruit", "vegetable", "bread", "salad", "sandwich", "pizza", "pasta",
        "rice", "meat", "dessert", "cake", "drink", "beverage", "coffee", "soup", "burger", "sushi",
        "breakfast", "snack", "baked_goods", "cookie", "cheese", "egg", "noodle", "seafood", "chicken",
    ]

    /// Returns the probability (0–1) that the image contains food, using Apple's
    /// on-device classifier. Returns 1 on failure so the server remains the judge.
    static func foodLikelihood(of image: UIImage) async -> Double {
        guard let cgImage = image.cgImage else { return 1 }
        do {
            let request = ClassifyImageRequest()
            let observations = try await request.perform(on: cgImage, orientation: .init(image.imageOrientation))
            let best = observations
                .filter { obs in foodKeywords.contains { obs.identifier.lowercased().contains($0) } }
                .map(\.confidence)
                .max() ?? 0
            return Double(best)
        } catch {
            return 1
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
