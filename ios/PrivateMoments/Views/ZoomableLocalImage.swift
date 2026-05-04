import SwiftUI
import UIKit

struct ZoomableLocalImage: View {
    @Environment(\.appLanguage) private var appLanguage

    let path: String
    let resetToken: Int
    let onSingleTap: () -> Void

    var body: some View {
        if let image = UIImage(contentsOfFile: path) {
            NativeZoomableImage(
                image: image,
                imageID: path,
                resetToken: resetToken,
                onSingleTap: onSingleTap
            )
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                Text(L10n.t("Image unavailable", appLanguage))
                    .font(.subheadline)
            }
            .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct NativeZoomableImage: UIViewRepresentable {
    let image: UIImage
    let imageID: String
    let resetToken: Int
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> SystemZoomImageScrollView {
        let scrollView = SystemZoomImageScrollView()
        scrollView.delegate = context.coordinator
        context.coordinator.scrollView = scrollView
        scrollView.installTapRecognizers(target: context.coordinator)
        return scrollView
    }

    func updateUIView(_ scrollView: SystemZoomImageScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        scrollView.setImage(image, id: imageID)

        if context.coordinator.lastResetToken == nil {
            context.coordinator.lastResetToken = resetToken
        } else if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            scrollView.resetZoom(animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var scrollView: SystemZoomImageScrollView?
        var onSingleTap: () -> Void
        var lastResetToken: Int?

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? SystemZoomImageScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let scrollView = scrollView as? SystemZoomImageScrollView else {
                return
            }

            scrollView.centerImage()
            scrollView.updatePanAvailability()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            guard let scrollView = scrollView as? SystemZoomImageScrollView else {
                return
            }

            scrollView.centerImage()
            scrollView.updatePanAvailability()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView else {
                return true
            }

            return !scrollView.isZoomed
        }

        @objc func handleSingleTap() {
            onSingleTap()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else {
                return
            }

            let point = recognizer.location(in: scrollView.imageView)
            scrollView.toggleZoom(at: point)
        }
    }
}

private final class SystemZoomImageScrollView: UIScrollView {
    let imageView = UIImageView()

    private var currentImageID: String?
    private var configuredSize: CGSize = .zero
    private var configuredImageSize: CGSize = .zero

    var isZoomed: Bool {
        zoomScale > minimumZoomScale * 1.01
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureZoomScalesIfNeeded()
        centerImage()
        updatePanAvailability()
    }

    func setImage(_ image: UIImage, id: String) {
        guard currentImageID != id || imageView.image == nil else {
            return
        }

        currentImageID = id
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        configuredSize = .zero
        configuredImageSize = .zero
        setNeedsLayout()
    }

    func installTapRecognizers(target: NativeZoomableImage.Coordinator) {
        let singleTap = UITapGestureRecognizer(target: target, action: #selector(NativeZoomableImage.Coordinator.handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.delegate = target

        let doubleTap = UITapGestureRecognizer(target: target, action: #selector(NativeZoomableImage.Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = target

        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
    }

    func resetZoom(animated: Bool) {
        setZoomScale(minimumZoomScale, animated: animated)
        centerImage()
        updatePanAvailability()
    }

    func toggleZoom(at point: CGPoint) {
        if isZoomed {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(maximumZoomScale, minimumZoomScale * 2.65)
        let zoomRect = CGRect(
            x: point.x - bounds.width / targetScale / 2,
            y: point.y - bounds.height / targetScale / 2,
            width: bounds.width / targetScale,
            height: bounds.height / targetScale
        )

        zoom(to: zoomRect, animated: true)
    }

    func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    func updatePanAvailability() {
        panGestureRecognizer.isEnabled = isZoomed
    }

    private func configure() {
        backgroundColor = .clear
        clipsToBounds = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = true
        bouncesZoom = true
        decelerationRate = .fast
        delaysContentTouches = false
        canCancelContentTouches = true
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 1
        maximumZoomScale = 5

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
        updatePanAvailability()
    }

    private func configureZoomScalesIfNeeded() {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else {
            return
        }

        guard configuredSize != bounds.size || configuredImageSize != image.size else {
            return
        }

        let oldMinimumZoomScale = minimumZoomScale
        let oldRelativeScale = oldMinimumZoomScale > 0 ? zoomScale / oldMinimumZoomScale : 1
        let widthScale = bounds.width / image.size.width
        let heightScale = bounds.height / image.size.height
        let fittedScale = min(widthScale, heightScale)
        let newMinimumZoomScale = max(fittedScale, 0.0001)

        minimumZoomScale = newMinimumZoomScale
        maximumZoomScale = max(newMinimumZoomScale * 5, newMinimumZoomScale + 0.01)
        contentSize = image.size

        if configuredSize == .zero {
            zoomScale = newMinimumZoomScale
        } else {
            zoomScale = min(max(newMinimumZoomScale * oldRelativeScale, minimumZoomScale), maximumZoomScale)
        }

        configuredSize = bounds.size
        configuredImageSize = image.size
    }
}
