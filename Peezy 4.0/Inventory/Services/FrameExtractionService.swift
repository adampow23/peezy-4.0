import AVFoundation
import UIKit

@Observable
final class FrameExtractionService {
    var isExtracting = false
    var progress: Double = 0.0
    var extractedFrames: [ExtractedFrame] = []

    func extractFrames(
        from videoURL: URL,
        interval: TimeInterval = 2.5,
        maxDimension: CGFloat = 1280
    ) async throws -> [ExtractedFrame] {
        isExtracting = true
        progress = 0.0
        extractedFrames = []

        defer {
            isExtracting = false
        }

        let asset = AVURLAsset(url: videoURL)

        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw FrameExtractionError.unreadableVideo("Cannot load video at \(videoURL.path): \(error.localizedDescription)")
        }

        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else {
            throw FrameExtractionError.zeroDuration
        }

        // Calculate frame times at the given interval
        var requestedTimes: [CMTime] = []
        var currentTime: TimeInterval = 0
        while currentTime < durationSeconds {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            requestedTimes.append(cmTime)
            currentTime += interval
        }

        guard !requestedTimes.isEmpty else {
            throw FrameExtractionError.zeroDuration
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        let totalFrames = requestedTimes.count
        var allFrames: [ExtractedFrame] = []
        var processedCount = 0

        do {
            for await result in generator.images(for: requestedTimes) {
                processedCount += 1
                progress = Double(processedCount) / Double(totalFrames)

                let cgImage = result.image
                let uiImage = UIImage(cgImage: cgImage)
                let resizedImage = resizeImage(uiImage, maxDimension: maxDimension)
                let timestamp = CMTimeGetSeconds(result.requestedTime)

                let frame = ExtractedFrame(
                    image: resizedImage,
                    timestamp: timestamp,
                    index: allFrames.count,
                    sharpnessScore: 1.0
                )
                allFrames.append(frame)
            }
        } catch {
            if allFrames.isEmpty {
                throw FrameExtractionError.noFramesExtracted
            }
        }

        #if DEBUG
        print("[FrameExtraction] Extracted \(allFrames.count) frames from \(String(format: "%.1f", durationSeconds))s video")
        #endif

        guard !allFrames.isEmpty else {
            throw FrameExtractionError.noFramesExtracted
        }

        extractedFrames = allFrames
        progress = 1.0
        return allFrames
    }

    // MARK: - Private Helpers

    /// Resize image so longest edge is at most maxDimension
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longestEdge = max(size.width, size.height)

        guard longestEdge > maxDimension else { return image }

        let scale = maxDimension / longestEdge
        let newSize = CGSize(
            width: floor(size.width * scale),
            height: floor(size.height * scale)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Errors

enum FrameExtractionError: LocalizedError {
    case unreadableVideo(String)
    case zeroDuration
    case noFramesExtracted

    var errorDescription: String? {
        switch self {
        case .unreadableVideo(let msg): return msg
        case .zeroDuration: return "Video has zero duration"
        case .noFramesExtracted: return "No frames could be extracted from the video"
        }
    }
}
