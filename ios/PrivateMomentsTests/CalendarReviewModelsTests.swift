import XCTest
@testable import PrivateMoments

final class CalendarReviewModelsTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        self.calendar = calendar
        self.now = date(year: 2026, month: 4, day: 15, hour: 12)
    }

    func testMonthGridAlwaysIncludesContinuousEmptyDays() {
        let month = CalendarReviewBuilder.month(
            containing: date(year: 2026, month: 2, day: 8, hour: 12),
            items: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(month.days.count, 42)
        XCTAssertEqual(calendar.component(.weekday, from: month.days.first!.date), calendar.firstWeekday)
        XCTAssertFalse(month.containsMoments)
        XCTAssertTrue(month.days.allSatisfy { $0.items.isEmpty })
    }

    func testTodayFutureAndDensityBucketsAreDerivedFromLocalItems() {
        let month = CalendarReviewBuilder.month(
            containing: now,
            items: [
                item(id: "one", occurredAt: date(year: 2026, month: 4, day: 2, hour: 9)),
                item(id: "two-a", occurredAt: date(year: 2026, month: 4, day: 3, hour: 9)),
                item(id: "two-b", occurredAt: date(year: 2026, month: 4, day: 3, hour: 10)),
                item(id: "four-a", occurredAt: date(year: 2026, month: 4, day: 4, hour: 9)),
                item(id: "four-b", occurredAt: date(year: 2026, month: 4, day: 4, hour: 10)),
                item(id: "four-c", occurredAt: date(year: 2026, month: 4, day: 4, hour: 11)),
                item(id: "four-d", occurredAt: date(year: 2026, month: 4, day: 4, hour: 12)),
                item(id: "future", occurredAt: date(year: 2026, month: 4, day: 16, hour: 9)),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(day(in: month, day: 1).densityLevel, .none)
        XCTAssertEqual(day(in: month, day: 2).densityLevel, .light)
        XCTAssertEqual(day(in: month, day: 3).densityLevel, .medium)
        XCTAssertEqual(day(in: month, day: 4).densityLevel, .strong)
        XCTAssertEqual(day(in: month, day: 4).items.map(\.id), ["four-d", "four-c", "four-b", "four-a"])
        XCTAssertTrue(day(in: month, day: 15).isToday)
        XCTAssertTrue(day(in: month, day: 16).isFuture)
        XCTAssertFalse(day(in: month, day: 16).isSelectable)
    }

    func testDensityUsesVisibleMonthDynamicScaleForHighFrequencyMonths() {
        let month = CalendarReviewBuilder.month(
            containing: now,
            items: highFrequencyItems(),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(day(in: month, day: 1).densityLevel, .light)
        XCTAssertEqual(day(in: month, day: 2).densityLevel, .medium)
        XCTAssertEqual(day(in: month, day: 3).densityLevel, .strong)
        XCTAssertEqual(day(in: month, day: 4).densityLevel, .intense)
        XCTAssertEqual(day(in: month, day: 5).densityLevel, .peak)
    }

    func testMonthStatsSummarizeDailyCountsAndContentTypes() {
        let month = CalendarReviewBuilder.month(
            containing: now,
            items: [
                item(
                    id: "text",
                    text: "Plain note",
                    occurredAt: date(year: 2026, month: 4, day: 1, hour: 9),
                    isFavorite: true,
                    comments: [comment(postId: "text")]
                ),
                item(id: "image", occurredAt: date(year: 2026, month: 4, day: 2, hour: 9), media: [media(kind: "image")]),
                item(id: "audio", occurredAt: date(year: 2026, month: 4, day: 2, hour: 10), media: [media(kind: "audio")]),
                item(id: "video", occurredAt: date(year: 2026, month: 4, day: 3, hour: 9), media: [media(kind: "video")]),
            ],
            now: now,
            calendar: calendar
        )

        let stats = month.stats
        XCTAssertEqual(stats.totalMoments, 4)
        XCTAssertEqual(stats.activeDays, 3)
        XCTAssertEqual(stats.maxDayCount, 2)
        XCTAssertEqual(stats.textOnlyMoments, 1)
        XCTAssertEqual(stats.imageCount, 1)
        XCTAssertEqual(stats.audioCount, 1)
        XCTAssertEqual(stats.videoCount, 1)
        XCTAssertEqual(stats.favoriteMoments, 1)
        XCTAssertEqual(stats.commentedMoments, 1)
        XCTAssertEqual(stats.busiestDay?.count, 2)
        XCTAssertEqual(calendar.component(.day, from: stats.busiestDay!.date), 2)
    }

    func testCheckInsContributeToCalendarActivityEvenWhenHiddenFromTimeline() {
        let hiddenCheckIn = checkIn(
            id: "meal-hidden",
            itemId: "meal",
            itemName: "Meal",
            occurredAt: date(year: 2026, month: 4, day: 2, hour: 12),
            showInTimeline: false
        )
        let visibleCheckIn = checkIn(
            id: "workout-visible",
            itemId: "workout",
            itemName: "Workout",
            occurredAt: date(year: 2026, month: 4, day: 3, hour: 18),
            showInTimeline: true
        )

        let month = CalendarReviewBuilder.month(
            containing: now,
            items: [
                item(id: "moment", occurredAt: date(year: 2026, month: 4, day: 2, hour: 9)),
            ],
            checkIns: [hiddenCheckIn, visibleCheckIn],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(day(in: month, day: 2).activityCount, 2)
        XCTAssertEqual(day(in: month, day: 2).checkIns.map(\.id), ["meal-hidden"])
        XCTAssertEqual(day(in: month, day: 3).activityCount, 1)
        XCTAssertEqual(month.stats.totalMoments, 1)
        XCTAssertEqual(month.stats.totalCheckIns, 2)
        XCTAssertEqual(month.stats.totalActivity, 3)
        XCTAssertEqual(month.stats.activeDays, 2)
    }

    func testDayReviewFiltersMatchExpectedMomentAttributes() {
        let commented = item(
            id: "commented",
            occurredAt: date(year: 2026, month: 4, day: 4, hour: 9),
            comments: [comment(postId: "commented")]
        )
        let audio = item(
            id: "audio",
            occurredAt: date(year: 2026, month: 4, day: 4, hour: 11),
            isFavorite: true,
            media: [media(kind: "audio")]
        )

        XCTAssertTrue(CalendarDayReviewFilter.comments.includes(commented))
        XCTAssertTrue(CalendarDayReviewFilter.audio.includes(audio))
        XCTAssertTrue(CalendarDayReviewFilter.favorites.includes(audio))
        XCTAssertFalse(CalendarDayReviewFilter.photos.includes(audio))
        XCTAssertFalse(CalendarDayReviewFilter.allCases.contains { $0.rawValue == "summaries" })
    }

    func testDayReviewFilterSelectionTogglesMultipleFiltersAsUnion() {
        let photo = item(id: "photo", occurredAt: date(year: 2026, month: 4, day: 4, hour: 9), media: [media(kind: "image")])
        let audio = item(id: "audio", occurredAt: date(year: 2026, month: 4, day: 4, hour: 10), media: [media(kind: "audio")])
        let video = item(id: "video", occurredAt: date(year: 2026, month: 4, day: 4, hour: 11), media: [media(kind: "video")])

        var selection = CalendarDayReviewFilterSelection()
        XCTAssertTrue(selection.includes(photo))
        XCTAssertTrue(selection.isSelected(.all))

        selection.toggle(.photos)
        XCTAssertTrue(selection.includes(photo))
        XCTAssertFalse(selection.includes(audio))
        XCTAssertFalse(selection.isSelected(.all))
        XCTAssertTrue(selection.isSelected(.photos))

        selection.toggle(.audio)
        XCTAssertTrue(selection.includes(photo))
        XCTAssertTrue(selection.includes(audio))
        XCTAssertFalse(selection.includes(video))

        selection.toggle(.photos)
        XCTAssertFalse(selection.includes(photo))
        XCTAssertTrue(selection.includes(audio))

        selection.toggle(.all)
        XCTAssertTrue(selection.includes(photo))
        XCTAssertTrue(selection.includes(video))
        XCTAssertTrue(selection.isSelected(.all))
    }

    func testMediaHintsAreLimitedAndFiltersAreIndependentFromTimeline() {
        let month = CalendarReviewBuilder.month(
            containing: now,
            items: [
                item(id: "photo-fav", occurredAt: date(year: 2026, month: 4, day: 5, hour: 9), isFavorite: true, media: [media(kind: "image")]),
                item(id: "audio", occurredAt: date(year: 2026, month: 4, day: 6, hour: 9), media: [media(kind: "audio")]),
                item(id: "text", text: "Plain note", occurredAt: date(year: 2026, month: 4, day: 7, hour: 9)),
                item(id: "mixed", occurredAt: date(year: 2026, month: 4, day: 8, hour: 9), media: [
                    media(kind: "image"),
                    media(kind: "audio"),
                    media(kind: "video"),
                ]),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(day(in: month, day: 8).mediaHints, [.image, .audio])

        let favoritePhotos = CalendarReviewBuilder.month(
            containing: now,
            items: month.days.flatMap(\.items),
            now: now,
            calendar: calendar,
            mediaFilter: .photos,
            favoritesOnly: true
        )
        XCTAssertEqual(day(in: favoritePhotos, day: 5).items.map(\.id), ["photo-fav"])
        XCTAssertTrue(day(in: favoritePhotos, day: 6).items.isEmpty)

        let textOnly = CalendarReviewBuilder.month(
            containing: now,
            items: month.days.flatMap(\.items),
            now: now,
            calendar: calendar,
            mediaFilter: .text
        )
        XCTAssertEqual(day(in: textOnly, day: 7).items.map(\.id), ["text"])
        XCTAssertTrue(day(in: textOnly, day: 5).items.isEmpty)

        let commentedOnly = CalendarReviewBuilder.month(
            containing: now,
            items: [
                item(id: "with-comment", occurredAt: date(year: 2026, month: 4, day: 9, hour: 9), comments: [comment(postId: "with-comment")]),
                item(id: "without-comment", occurredAt: date(year: 2026, month: 4, day: 10, hour: 9)),
            ],
            now: now,
            calendar: calendar,
            commentsOnly: true
        )
        XCTAssertEqual(day(in: commentedOnly, day: 9).items.map(\.id), ["with-comment"])
        XCTAssertTrue(day(in: commentedOnly, day: 10).items.isEmpty)
    }

    private func day(in month: CalendarReviewMonth, day: Int) -> CalendarReviewDay {
        month.days.first {
            $0.isInDisplayedMonth && calendar.component(.day, from: $0.date) == day
        }!
    }

    private func item(
        id: String,
        text: String = "",
        occurredAt: Date,
        isFavorite: Bool = false,
        media: [TimelineMedia] = [],
        comments: [TimelineComment] = [],
        summaries: [TimelineAISummary] = []
    ) -> TimelineItem {
        TimelineItem(
            post: TimelinePost(
                id: id,
                text: text,
                isFavorite: isFavorite,
                isPinned: false,
                pinnedAt: nil,
                aiTagProcessedAt: nil,
                tagsUserEditedAt: nil,
                occurredAt: occurredAt,
                localCreatedAt: occurredAt,
                localUpdatedAt: occurredAt,
                localEditedAt: nil,
                serverVersion: nil,
                syncStatus: "synced",
                deletedAt: nil
            ),
            media: media,
            comments: comments,
            aiSummaries: summaries,
            tags: []
        )
    }

    private func highFrequencyItems() -> [TimelineItem] {
        [
            repeatedItems(prefix: "one", day: 1, count: 1),
            repeatedItems(prefix: "five", day: 2, count: 5),
            repeatedItems(prefix: "ten", day: 3, count: 10),
            repeatedItems(prefix: "fifteen", day: 4, count: 15),
            repeatedItems(prefix: "twenty-five", day: 5, count: 25),
        ].flatMap { $0 }
    }

    private func repeatedItems(prefix: String, day: Int, count: Int) -> [TimelineItem] {
        (0..<count).map { index in
            item(
                id: "\(prefix)-\(index)",
                occurredAt: date(year: 2026, month: 4, day: day, hour: min(23, index))
            )
        }
    }

    private func media(kind: String) -> TimelineMedia {
        TimelineMedia(
            id: UUID().uuidString,
            postId: "post",
            kind: kind,
            localCompressedPath: "",
            localOriginalStagingPath: nil,
            localThumbnailPath: nil,
            remoteCompressedPath: nil,
            remoteOriginalPath: nil,
            remoteThumbnailPath: nil,
            originalPreserved: false,
            uploadStatus: "uploaded",
            mimeType: nil,
            durationSeconds: nil,
            transcriptionText: nil,
            transcriptionStatus: "not_requested",
            transcriptionError: nil,
            transcriptionUpdatedAt: nil,
            sortOrder: 0,
            checksum: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func comment(postId: String) -> TimelineComment {
        TimelineComment(
            id: "\(postId)-comment",
            postId: postId,
            text: "Comment",
            createdAt: now,
            updatedAt: now,
            serverVersion: nil,
            deletedAt: nil
        )
    }

    private func checkIn(
        id: String,
        itemId: String,
        itemName: String,
        occurredAt: Date,
        showInTimeline: Bool
    ) -> CheckInFeedEntry {
        let item = CheckInItem(
            id: itemId,
            name: itemName,
            symbolName: "checkmark.circle",
            colorHex: "#61B88D",
            recordMode: .oncePerDay,
            timeVisualization: .none,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 0,
            defaultShowInTimeline: showInTimeline,
            tagId: nil,
            createdAt: occurredAt,
            updatedAt: occurredAt,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        )
        let entry = CheckInEntry(
            id: id,
            itemId: itemId,
            occurredAt: occurredAt,
            note: "",
            showInTimeline: showInTimeline,
            createdAt: occurredAt,
            updatedAt: occurredAt,
            deletedAt: nil,
            syncStatus: "synced"
        )

        return CheckInFeedEntry(entry: entry, item: item, tag: nil, media: [])
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
        return components.date!
    }
}
