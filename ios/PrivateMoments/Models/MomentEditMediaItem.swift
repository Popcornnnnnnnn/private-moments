import Foundation

struct MomentEditMediaItem: Identifiable {
    enum Source {
        case existing(TimelineMedia)
        case new(Data)
    }

    var id: String
    var source: Source
}
