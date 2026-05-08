import XCTest
@testable import PrivateMoments

final class TimelineDateJumpModelsTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        self.now = date(year: 2026, month: 4, day: 30, hour: 12)
    }

    func testEmptyItemsReturnNoGroups() {
        let groups = TimelineDateJumpBuilder.groups(from: [], now: now, calendar: calendar)

        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupsVisibleItemsByMonthAndDayNewestFirst() {
        let newestApril = item(id: "april-newest", occurredAt: date(year: 2026, month: 4, day: 29, hour: 18))
        let olderSameDay = item(id: "april-older-same-day", occurredAt: date(year: 2026, month: 4, day: 29, hour: 9))
        let olderApril = item(id: "april-older-day", occurredAt: date(year: 2026, month: 4, day: 2, hour: 7))
        let march = item(id: "march-visible", occurredAt: date(year: 2026, month: 3, day: 31, hour: 22))

        let groups = TimelineDateJumpBuilder.groups(
            from: [olderApril, march, olderSameDay, newestApril],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["April 2026", "March 2026"])
        XCTAssertEqual(groups.map(\.anchorItemID), ["april-newest", "march-visible"])
        XCTAssertEqual(groups[0].items.map(\.id), ["april-newest", "april-older-same-day", "april-older-day"])
        XCTAssertEqual(groups[0].days.map(\.targetItemID), ["april-newest", "april-older-day"])
        XCTAssertEqual(groups[0].days[0].items.map(\.id), ["april-newest", "april-older-same-day"])
        XCTAssertEqual(groups[1].days.map(\.targetItemID), ["march-visible"])
    }

    func testBuilderReadsOnlyItemsPassedByCaller() {
        let visible = item(id: "visible-favorite", occurredAt: date(year: 2026, month: 4, day: 20, hour: 12), isFavorite: true)
        let hiddenByCaller = item(id: "hidden-non-favorite", occurredAt: date(year: 2026, month: 5, day: 2, hour: 12), isFavorite: false)
        let filteredItems = [visible, hiddenByCaller].filter(\.post.isFavorite)

        let groups = TimelineDateJumpBuilder.groups(from: filteredItems, now: now, calendar: calendar)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "April 2026")
        XCTAssertEqual(groups.first?.anchorItemID, "visible-favorite")
        XCTAssertFalse(groups.flatMap(\.items).contains { $0.id == hiddenByCaller.id })
    }

    func testDayJumpLabelsAreDateLanguageOnly() {
        let dates = [
            date(year: 2026, month: 4, day: 30, hour: 8),
            date(year: 2026, month: 4, day: 29, hour: 8),
            date(year: 2026, month: 5, day: 1, hour: 8),
            date(year: 2026, month: 4, day: 27, hour: 8),
            date(year: 2026, month: 4, day: 10, hour: 8),
            date(year: 2025, month: 12, day: 31, hour: 8),
        ]

        let labels = dates.map { MomentDateFormatter.dayJumpTitle(for: $0, now: now, calendar: calendar) }

        XCTAssertEqual(labels, ["Today", "Yesterday", "Tomorrow", "Monday", "Apr 10", "Dec 31, 2025"])
        labels.forEach { assertCountFreeLabel($0) }
    }

    func testGroupedDayLabelsAreCountFree() {
        let groups = TimelineDateJumpBuilder.groups(
            from: [
                item(id: "today-a", occurredAt: date(year: 2026, month: 4, day: 30, hour: 9)),
                item(id: "today-b", occurredAt: date(year: 2026, month: 4, day: 30, hour: 8)),
            ],
            now: now,
            calendar: calendar
        )

        let labels = groups.flatMap(\.days).map(\.title)
        XCTAssertEqual(labels, ["Today"])
        labels.forEach { assertCountFreeLabel($0) }
    }

    private func assertCountFreeLabel(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(label.localizedCaseInsensitiveContains("moment"), "Label includes moment wording: \(label)", file: file, line: line)
        XCTAssertNil(label.range(of: #"\b\d+\s+moments?\b"#, options: [.regularExpression, .caseInsensitive]), "Label includes count wording: \(label)", file: file, line: line)
        XCTAssertNil(label.range(of: #"\(\s*\d+\s*\)$"#, options: .regularExpression), "Label ends with a parenthesized count: \(label)", file: file, line: line)
    }

    private func item(
        id: String,
        occurredAt: Date,
        isFavorite: Bool = false,
        media: [TimelineMedia] = []
    ) -> TimelineItem {
        TimelineItem(
            post: TimelinePost(
                id: id,
                text: "Fixture \(id)",
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
            comments: [],
            aiSummaries: [],
            tags: []
        )
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
