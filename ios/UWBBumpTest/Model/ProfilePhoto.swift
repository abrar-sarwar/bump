import UIKit

/// Profile photos: small, square JPEGs kept inside the profile.
///
/// A photo is part of the card, so it goes only to a confirmed partner over the
/// direct link, never to the BUMP server or xAI. It has to fit in one bounded
/// wire frame (`Wire.maxFrame`, 64 KB, and JSON base64 adds a third), so it is
/// cropped square, scaled down and compressed until it is under `maxBytes`.
enum ProfilePhoto {
    static let side: CGFloat = 320
    static let maxBytes = 30_000
    /// What we accept from a partner. A little slack over our own limit.
    static let maxIncomingBytes = 40_000

    /// Turn any picked image into a small square JPEG, or nil if unreadable.
    static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let square = cropSquare(image)
        var side = Self.side
        while side >= 120 {
            let scaled = resize(square, to: side)
            for quality in stride(from: 0.8, through: 0.35, by: -0.15) {
                if let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                    return jpeg
                }
            }
            side -= 60
        }
        return nil
    }

    /// Budget for `prepareThumbnail`. Far smaller than `maxBytes`: StreetPass's
    /// ambient `.hello` frame is capped at `StreetPassWire.maxFrame` (16 KB, a
    /// quarter of `Wire.maxFrame`), and JSON base64 adds a third on top, so the
    /// encoded avatar has to stay well under half that cap to leave room for the
    /// envelope, the display name and up to five `Interest`s.
    static let thumbnailMaxBytes = 4_000
    static let thumbnailSide: CGFloat = 96

    /// A much smaller thumbnail for payloads that must stay tiny — StreetPass's
    /// ambient broadcast, bounded by `StreetPassWire.maxFrame`, rather than the
    /// profile card's far roomier 64 KB wire frame. Same crop/scale/compress
    /// discipline as `prepare`, just a much tighter budget. nil if unreadable
    /// or if even the smallest attempt can't fit.
    static func prepareThumbnail(_ data: Data,
                                 maxBytes: Int = thumbnailMaxBytes,
                                 side: CGFloat = thumbnailSide) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let square = cropSquare(image)
        var currentSide = side
        while currentSide >= 48 {
            let scaled = resize(square, to: currentSide)
            for quality in stride(from: 0.8, through: 0.35, by: -0.15) {
                if let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count <= maxBytes {
                    return jpeg
                }
            }
            currentSide -= 16
        }
        return nil
    }

    /// Drop a partner's photo if it's too big or isn't an image.
    static func sanitized(_ data: Data?) -> Data? {
        guard let data, data.count <= maxIncomingBytes, UIImage(data: data) != nil else { return nil }
        return data
    }

    private static func cropSquare(_ image: UIImage) -> UIImage {
        let size = image.size
        let edge = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - edge) / 2, y: (size.height - edge) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format).image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }

    private static func resize(_ image: UIImage, to side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}
