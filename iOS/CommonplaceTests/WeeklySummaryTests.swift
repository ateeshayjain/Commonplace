import XCTest
@testable import Commonplace

/// The Weekly Summary's numbers (ProfileViewModel), from the demo saves
@MainActor
final class WeeklySummaryTests: XCTestCase {
    private func viewModel() -> ProfileViewModel {
        let model = ProfileViewModel()
        model.weeklyDocuments = DocumentService.shared.fetchDemoDocuments()
            .filter { $0.createdAt >= ProfileViewModel.weekStart }
        return model
    }

    func testWindowIsTodayAndTheSixDaysBefore() {
        let calendar = Calendar.current
        let start = ProfileViewModel.weekStart
        XCTAssertEqual(start, calendar.startOfDay(for: start))
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: Date())).day, 6)
    }

    func testSavesPerDayCoversSevenDaysAndEverySave() {
        let model = viewModel()
        XCTAssertEqual(model.savesPerDay.count, 7)
        XCTAssertEqual(model.savesPerDay.map(\.count).reduce(0, +), model.weeklyDocuments.count)
        XCTAssertEqual(model.savesPerDay.map(\.day), model.savesPerDay.map(\.day).sorted())
    }

    func testHistoryGroupsByDayNewestFirst() {
        let model = viewModel()
        let groups = model.weeklyDocumentsByDay
        XCTAssertEqual(groups.map(\.day), groups.map(\.day).sorted(by: >))
        XCTAssertEqual(groups.flatMap(\.documents).count, model.weeklyDocuments.count)
        for group in groups {
            XCTAssertEqual(group.documents.map(\.createdAt), group.documents.map(\.createdAt).sorted(by: >))
        }
    }

    func testCategoriesAreCountedMostCommonFirst() {
        let categories = viewModel().weeklyCategories
        XCTAssertEqual(categories.first?.name, "Technology")
        XCTAssertEqual(categories.map(\.count), categories.map(\.count).sorted(by: >))
    }

    func testSourcesCountEachSave() {
        let model = viewModel()
        XCTAssertEqual(model.weeklySources.map(\.count).reduce(0, +), model.weeklyDocuments.count)
    }

    func testReadingTimeFormat() {
        let model = ProfileViewModel()
        model.totalReadingMinutes = 45
        XCTAssertEqual(model.formattedReadingTime, "45m")
        model.totalReadingMinutes = 120
        XCTAssertEqual(model.formattedReadingTime, "2h")
        model.totalReadingMinutes = 146
        XCTAssertEqual(model.formattedReadingTime, "2h 26m")
    }
}
