import SwiftUI
import UIKit

struct TimelineRow: View {
    let item: TimelineItem
    let onOpenMedia: ([TimelineMedia], Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(MomentDateFormatter.timelineLabel(for: item.post.occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if item.post.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorite")
                }
                SyncBadge(status: item.post.syncStatus)
            }

            if !item.post.text.isEmpty {
                Text(item.post.text)
                    .font(.body)
                    .textSelection(.enabled)
            }

            if !item.media.isEmpty {
                if item.media.count == 1, let media = item.media.first {
                    Button {
                        onOpenMedia(item.media, 0)
                    } label: {
                        TimelineImage(media: media, style: .single)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open image")
                } else {
                    LazyVGrid(columns: imageColumns, spacing: 6) {
                        ForEach(Array(item.media.enumerated()), id: \.element.id) { index, media in
                            Button {
                                onOpenMedia(item.media, index)
                            } label: {
                                TimelineImage(media: media, style: .grid)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open image \(index + 1)")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var imageColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: item.media.count == 1 ? 1 : 3)
    }
}

enum TimelineImageStyle {
    case single
    case grid
}

struct TimelineImage: View {
    let media: TimelineMedia
    let style: TimelineImageStyle

    var body: some View {
        Group {
            switch style {
            case .single:
                singleImage
            case .grid:
                gridImage
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var singleImage: some View {
        if let image = UIImage(contentsOfFile: media.localCompressedPath) {
            let aspectRatio = image.size.width / max(image.size.height, 1)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
        } else {
            ZStack {
                Color(.secondarySystemBackground)
                PlaceholderImage()
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private var gridImage: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.secondarySystemBackground)

                if let image = UIImage(contentsOfFile: media.localCompressedPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    PlaceholderImage()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PlaceholderImage: View {
    var body: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SyncBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch status {
        case "synced":
            return Color.green.opacity(0.16)
        case "failed":
            return Color.red.opacity(0.16)
        case "partial":
            return Color.blue.opacity(0.16)
        default:
            return Color.orange.opacity(0.16)
        }
    }

    private var foreground: Color {
        switch status {
        case "synced":
            return Color.green
        case "failed":
            return Color.red
        case "partial":
            return Color.blue
        default:
            return Color.orange
        }
    }
}
