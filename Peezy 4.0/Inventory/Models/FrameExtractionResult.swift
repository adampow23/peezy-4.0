import UIKit

struct ExtractedFrame {
    let image: UIImage
    let timestamp: TimeInterval    // Position in video
    let index: Int                 // Frame number (0-based)
    let sharpnessScore: Double     // Laplacian variance (higher = sharper)
}
