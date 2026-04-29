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
        let groups = TimelineDateJumpBuilder.groups(from: [], calendar: calendar)

        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupsVisibleItemsByMonthNewestFirst() {
        let newestApril = item(id: "april-newest", occurredAt: date(year: 2026, month: 4, day: 29, hour: 18))
        let olderSameDay = item(id: "april-older-same-day", occurredAt: date(year: 2026, month: 4, day: 29, hour: 9))
        let olderApril = item(id: "april-older-day", occurredAt: date(year: 2026, month: 4, day: 2, hour: 7))
        let march = item(id: "march-visible", occurredAt: date(year: 2026, month: 3, day: 31, hour: 22))

        let groups = TimelineDateJumpBuilder.groups(
            from: [olderApril, march, olderSameDay, newestApril],
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.title), ["April 2026", "March 2026"])
        XCTAssertEqual(groups.map(\.menuTitle), ["Apr 2026", "Mar 2026"])
        XCTAssertEqual(groups.map(\.anchorItemID), ["april-newest", "march-visible"])
        XCTAssertEqual(groups[0].items.map(\.id), ["april-newest", "april-older-same-day", "april-older-day"])
        XCTAssertEqual(groups[1].items.map(\.id), ["march-visible"])
    }

    func testBuilderReadsOnlyItemsPassedByCaller() {
        let visible = item(id: "visible-favorite", occurredAt: date(year: 2026, month: 4, day: 20, hour: 12), isFavorite: true)
        let hiddenByCaller = item(id: "hidden-non-favorite", occurredAt: date(year: 2026, month: 5, day: 2, hour: 12), isFavorite: false)
        let filteredItems = [visible, hiddenByCaller].filter(\.post.isFavorite)

        let groups = TimelineDateJumpBuilder.groups(from: filteredItems, calendar: calendar)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.title, "April 2026")
        XCTAssertEqual(groups.first?.menuTitle, "Apr 2026")
        XCTAssertEqual(groups.first?.anchorItemID, "visible-favorite")
        XCTAssertFalse(groups.flatMap(\.items).contains { $0.id == hiddenByCaller.id })
    }

    func testMonthLabelsAreCountFree() {
        let groups = TimelineDateJumpBuilder.groups(
            from: [
                item(id: "today-a", occurredAt: date(year: 2026, month: 4, day: 30, hour: 9)),
                item(id: "today-b", occurredAt: date(year: 2026, month: 4, day: 30, hour: 8)),
            ],
            calendar: calendar
        )

        let labels = groups.flatMap { [$0.title, $0.menuTitle] }
        XCTAssertEqual(labels, ["April 2026", "Apr 2026"])
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
                occurredAt: occurredAt,
                localCreatedAt: occurredAt,
                localUpdatedAt: occurredAt,
                localEditedAt: nil,
                serverVersion: nil,
                syncStatus: "synced",
                deletedAt: nil
            ),
            media: media,
            comments: []
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
