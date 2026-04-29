import UIKit

enum ImageCompression {
    static let maxUploadEdge: CGFloat = 1600
    static let uploadJPEGQuality: CGFloat = 0.72

    static func uploadJPEGData(from image: UIImage) -> Data? {
        let resizedImage = resized(image, maxEdge: maxUploadEdge)
        return resizedImage.jpegData(compressionQuality: uploadJPEGQuality)
    }

    private static func resized(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        let longestEdge = max(width, height)

        guard longestEdge > maxEdge, width > 0, height > 0 else {
            return image
        }

        let scale = maxEdge / longestEdge
        let targetSize = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
