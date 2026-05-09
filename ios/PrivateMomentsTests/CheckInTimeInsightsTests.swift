import XCTest
import CoreGraphics
@testable import PrivateMoments

final class CheckInTimeInsightsTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    func testTimeLineBuildsDataWindowWithGapsAndDynamicBounds() {
        let item = checkInItem(mode: .oncePerDay, visualization: .timeLine)
        let now = date(2026, 5, 30, 12, 0)
        let insight = CheckInTimeInsightsBuilder.lineInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "early", at: date(2026, 5, 27, 7, 30)),
                entry(itemId: item.id, id: "late", at: date(2026, 5, 28, 11, 30)),
                entry(itemId: item.id, id: "today", at: date(2026, 5, 30, 8, 0)),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(insight.points.count, 4)
        XCTAssertEqual(insight.points.first?.day, calendar.startOfDay(for: date(2026, 5, 27, 12, 0)))
        XCTAssertEqual(insight.points.last?.day, calendar.startOfDay(for: now))
        XCTAssertFalse(insight.usesOvernightExpansion)
        XCTAssertEqual(insight.points.compactMap(\.plottedMinute), [450, 690, 480])
        XCTAssertTrue(insight.points.contains { $0.entry == nil })
        XCTAssertLessThanOrEqual(insight.lowerMinute, 390)
        XCTAssertGreaterThanOrEqual(insight.upperMinute, 750)
    }

    func testTimeLineStartsTodayAtLeadingEdgeWhenThereIsNoHistory() {
        let item = checkInItem(mode: .oncePerDay, visualization: .timeLine)
        let now = date(2026, 5, 30, 12, 0)
        let insight = CheckInTimeInsightsBuilder.lineInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "today", at: date(2026, 5, 30, 8, 0)),
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(insight.points.count, 1)
        XCTAssertEqual(insight.points.first?.day, calendar.startOfDay(for: now))
        XCTAssertEqual(insight.points.first?.plottedMinute, 480)
    }

    func testTimeLineLayoutSelectsNearestRealDataPoint() {
        let item = checkInItem(mode: .oncePerDay, visualization: .timeLine)
        let now = date(2026, 5, 30, 12, 0)
        let insight = CheckInTimeInsightsBuilder.lineInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "first", at: date(2026, 5, 27, 7, 30)),
                entry(itemId: item.id, id: "second", at: date(2026, 5, 28, 11, 30)),
                entry(itemId: item.id, id: "today", at: date(2026, 5, 30, 8, 0)),
            ],
            now: now,
            calendar: calendar
        )
        let layout = CheckInTimeLineChartLayout(insight: insight, size: CGSize(width: 212, height: 156))

        XCTAssertEqual(layout.nearestDataPointIndex(toX: 0), 0)
        XCTAssertEqual(layout.nearestDataPointIndex(toX: 74), 1)
        XCTAssertEqual(layout.nearestDataPointIndex(toX: 140), 3)
        XCTAssertEqual(layout.nearestDataPointIndex(toX: 260), 3)
    }

    func testTimeLineLayoutKeepsSingleTodayPointSelectableAtLeadingEdge() {
        let item = checkInItem(mode: .oncePerDay, visualization: .timeLine)
        let now = date(2026, 5, 30, 12, 0)
        let insight = CheckInTimeInsightsBuilder.lineInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "today", at: date(2026, 5, 30, 8, 0)),
            ],
            now: now,
            calendar: calendar
        )
        let layout = CheckInTimeLineChartLayout(insight: insight, size: CGSize(width: 212, height: 156))

        XCTAssertEqual(layout.plotPoints.first?.position.x, 6)
        XCTAssertEqual(layout.nearestDataPointIndex(toX: 0), 0)
        XCTAssertEqual(layout.nearestDataPointIndex(toX: 212), 0)
    }

    func testTimeLineExpandsOvernightTimesIntoOneContinuousRange() {
        let item = checkInItem(mode: .oncePerDay, visualization: .timeLine)
        let insight = CheckInTimeInsightsBuilder.lineInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "night", at: date(2026, 5, 27, 23, 30)),
                entry(itemId: item.id, id: "after-midnight", at: date(2026, 5, 28, 0, 30)),
                entry(itemId: item.id, id: "late-night", at: date(2026, 5, 29, 1, 10)),
            ],
            now: date(2026, 5, 30, 12, 0),
            calendar: calendar
        )

        XCTAssertTrue(insight.usesOvernightExpansion)
        XCTAssertEqual(insight.points.compactMap(\.plottedMinute), [1_410, 1_470, 1_510])
        XCTAssertEqual(CheckInTimeInsightsBuilder.timeLabel(for: 1_470), "00:30")
    }

    func testHeatmapUsesOneHourBucketsAndCountsMultipleEntriesPerDay() {
        let item = checkInItem(mode: .multiplePerDay, visualization: .timeHeatmap)
        let insight = CheckInTimeInsightsBuilder.heatmapInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "coffee-1", at: date(2026, 5, 28, 9, 5)),
                entry(itemId: item.id, id: "coffee-2", at: date(2026, 5, 28, 9, 45)),
                entry(itemId: item.id, id: "coffee-3", at: date(2026, 5, 28, 15, 0)),
                entry(itemId: "other", id: "other", at: date(2026, 5, 28, 9, 30)),
            ],
            now: date(2026, 5, 30, 12, 0),
            calendar: calendar
        )

        XCTAssertEqual(insight.totalEntries, 3)
        XCTAssertEqual(insight.hourBuckets.first { $0.hour == 9 }?.count, 2)
        XCTAssertEqual(insight.hourBuckets.first { $0.hour == 15 }?.count, 1)
        XCTAssertEqual(insight.maxCount, 2)
        XCTAssertEqual(
            insight.weekdayHourBuckets.first { $0.weekday == 5 && $0.hour == 9 }?.count,
            2
        )
    }

    func testHeatmapSelectionReturnsMatchingEntriesNewestFirst() {
        let item = checkInItem(mode: .multiplePerDay, visualization: .timeHeatmap)
        let insight = CheckInTimeInsightsBuilder.heatmapInsight(
            item: item,
            entries: [
                entry(itemId: item.id, id: "morning-old", at: date(2026, 5, 27, 9, 5)),
                entry(itemId: item.id, id: "morning-new", at: date(2026, 5, 28, 9, 45)),
                entry(itemId: item.id, id: "afternoon", at: date(2026, 5, 28, 15, 0)),
                entry(itemId: item.id, id: "other-weekday", at: date(2026, 5, 29, 9, 15)),
            ],
            now: date(2026, 5, 30, 12, 0),
            calendar: calendar
        )

        XCTAssertEqual(
            insight.entries(for: CheckInHeatmapSelection(weekday: nil, hour: 9), calendar: calendar).map(\.id),
            ["other-weekday", "morning-new", "morning-old"]
        )
        XCTAssertEqual(
            insight.entries(for: CheckInHeatmapSelection(weekday: 5, hour: 9), calendar: calendar).map(\.id),
            ["morning-new"]
        )
    }

    private func checkInItem(
        mode: CheckInRecordMode,
        visualization: CheckInTimeVisualization
    ) -> CheckInItem {
        let now = date(2026, 5, 1, 12, 0)
        return CheckInItem(
            id: "item",
            name: "Check-in",
            symbolName: "checkmark.circle",
            colorHex: "#61B88D",
            recordMode: mode,
            timeVisualization: visualization,
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
