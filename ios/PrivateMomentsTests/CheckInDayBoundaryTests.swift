import XCTest
@testable import PrivateMoments

final class CheckInDayBoundaryTests: XCTestCase {
    private var temporaryRoot: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "CheckInDayBoundaryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        try super.tearDownWithError()
    }

    func testCustomDayStartAllowsTwoBedtimesOnOneCalendarDate() throws {
        let database = try LocalDatabase.openForTesting(url: temporaryRoot.appending(path: "test.sqlite"))
        let item = checkInItem(dayStartHour: 12)
        let afterMidnight = entry(itemId: item.id, id: "after-midnight", at: date(2026, 5, 28, 0, 30))

        try database.upsertCheckInItem(item, operation: nil)
        try database.upsertCheckInEntry(afterMidnight, operation: nil)

        XCTAssertTrue(try database.hasCheckInEntry(
            itemId: item.id,
            on: date(2026, 5, 28, 10, 0),
            dayStartHour: item.dayStartHour,
            calendar: calendar
        ))
        XCTAssertFalse(try database.hasCheckInEntry(
            itemId: item.id,
            on: date(2026, 5, 28, 23, 30),
            dayStartHour: item.dayStartHour,
            calendar: calendar
        ))
        XCTAssertTrue(try database.hasCheckInEntry(
            itemId: item.id,
            on: date(2026, 5, 28, 23, 30),
            calendar: calendar
        ))
    }

    private func checkInItem(dayStartHour: Int) -> CheckInItem {
        let now = date(2026, 5, 1, 12, 0)
        return CheckInItem(
            id: "bed",
            name: "Bed",
            symbolName: "bed.double",
            colorHex: "#7A8FB8",
            recordMode: .oncePerDay,
            timeVisualization: .timeLine,
            dayStartHour: dayStartHour,
            activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
            sortOrder: 0,
            defaultShowInTimeline: false,
            tagId: nil,
            createdAt: now,
            updatedAt: now,
            archivedAt: nil,
            deletedAt: nil,
            syncStatus: "synced"
        )
    }

    private func entry(itemId: String, id: String, at occurredAt: Date) -> CheckInEntry {
        CheckInEntry(
            id: id,
            itemId: itemId,
            occurredAt: occurredAt,
            note: "",
            showInTimeline: false,
            createdAt: occurredAt,
            updatedAt: occurredAt,
            deletedAt: nil,
            syncStatus: "synced"
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ).date!
    }
}
