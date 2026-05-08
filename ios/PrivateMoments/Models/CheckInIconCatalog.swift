import Foundation
import UIKit

struct CheckInIconPreset: Identifiable, Hashable {
    let symbolName: String
    let title: String
    let keywords: [String]

    var id: String {
        symbolName
    }

    init(symbolName: String, title: String, keywords: [String] = []) {
        self.symbolName = symbolName
        self.title = title
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        let searchable = ([symbolName, title] + keywords).joined(separator: " ").lowercased()
        return searchable.contains(query.lowercased())
    }
}

struct CheckInIconCategory: Identifiable, Hashable {
    static let allId = "all"

    let id: String
    let title: String
    let presets: [CheckInIconPreset]
}

enum CheckInSymbolValidator {
    static let fallbackSymbolName = "checkmark.circle"

    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallbackSymbolName
        }

        return isValid(trimmed) ? trimmed : fallbackSymbolName
    }

    static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        return UIImage(systemName: trimmed) != nil
    }
}

enum CheckInIconCatalog {
    static let categories: [CheckInIconCategory] = [
        CheckInIconCategory(
            id: "daily",
            title: "Daily",
            presets: [
                CheckInIconPreset(symbolName: "checkmark.circle", title: "Check", keywords: ["done", "complete"]),
                CheckInIconPreset(symbolName: "star", title: "Priority", keywords: ["favorite", "important"]),
                CheckInIconPreset(symbolName: "flag", title: "Goal", keywords: ["target", "milestone"]),
                CheckInIconPreset(symbolName: "bell", title: "Reminder", keywords: ["alert", "routine"]),
                CheckInIconPreset(symbolName: "clock", title: "Time", keywords: ["schedule"]),
                CheckInIconPreset(symbolName: "timer", title: "Timer", keywords: ["focus"]),
                CheckInIconPreset(symbolName: "calendar", title: "Calendar", keywords: ["date"]),
                CheckInIconPreset(symbolName: "target", title: "Target", keywords: ["goal"]),
                CheckInIconPreset(symbolName: "bolt", title: "Energy", keywords: ["power"]),
                CheckInIconPreset(symbolName: "flame", title: "Flame", keywords: ["heat"]),
                CheckInIconPreset(symbolName: "sparkles", title: "Clean", keywords: ["fresh"]),
                CheckInIconPreset(symbolName: "list.bullet", title: "List", keywords: ["task"])
            ]
        ),
        CheckInIconCategory(
            id: "food",
            title: "Food",
            presets: [
                CheckInIconPreset(symbolName: "fork.knife", title: "Meal", keywords: ["food", "eat", "dinner"]),
                CheckInIconPreset(symbolName: "cup.and.saucer", title: "Coffee", keywords: ["tea", "drink"]),
                CheckInIconPreset(symbolName: "takeoutbag.and.cup.and.straw", title: "Takeout", keywords: ["lunch", "drink"]),
                CheckInIconPreset(symbolName: "carrot", title: "Vegetable", keywords: ["diet", "healthy"]),
                CheckInIconPreset(symbolName: "leaf", title: "Diet", keywords: ["green", "healthy"]),
                CheckInIconPreset(symbolName: "drop", title: "Water", keywords: ["hydrate", "drink"]),
                CheckInIconPreset(symbolName: "wineglass", title: "Drink", keywords: ["wine"]),
                CheckInIconPreset(symbolName: "birthday.cake", title: "Treat", keywords: ["cake", "sweet"]),
                CheckInIconPreset(symbolName: "fish", title: "Protein", keywords: ["meal"]),
                CheckInIconPreset(symbolName: "cart", title: "Groceries", keywords: ["shopping"])
            ]
        ),
        CheckInIconCategory(
            id: "movement",
            title: "Movement",
            presets: [
                CheckInIconPreset(symbolName: "figure.walk", title: "Walk", keywords: ["steps"]),
                CheckInIconPreset(symbolName: "figure.run", title: "Run", keywords: ["workout"]),
                CheckInIconPreset(symbolName: "bicycle", title: "Cycling", keywords: ["bike"]),
                CheckInIconPreset(symbolName: "dumbbell", title: "Strength", keywords: ["gym", "weights"]),
                CheckInIconPreset(symbolName: "sportscourt", title: "Sport", keywords: ["court"]),
                CheckInIconPreset(symbolName: "figure.strengthtraining.traditional", title: "Training", keywords: ["exercise"]),
                CheckInIconPreset(symbolName: "figure.mind.and.body", title: "Mindful", keywords: ["yoga", "meditate"]),
                CheckInIconPreset(symbolName: "figure.pool.swim", title: "Swim", keywords: ["pool"]),
                CheckInIconPreset(symbolName: "figure.hiking", title: "Hike", keywords: ["outdoor"]),
                CheckInIconPreset(symbolName: "figure.cooldown", title: "Stretch", keywords: ["cooldown"])
            ]
        ),
        CheckInIconCategory(
            id: "health",
            title: "Health",
            presets: [
                CheckInIconPreset(symbolName: "heart", title: "Health", keywords: ["care"]),
                CheckInIconPreset(symbolName: "heart.fill", title: "Wellness", keywords: ["heart"]),
                CheckInIconPreset(symbolName: "pills", title: "Medicine", keywords: ["medication"]),
                CheckInIconPreset(symbolName: "cross.case", title: "Care", keywords: ["medical"]),
                CheckInIconPreset(symbolName: "medical.thermometer", title: "Temperature", keywords: ["fever"]),
                CheckInIconPreset(symbolName: "bandage", title: "Recovery", keywords: ["injury"]),
                CheckInIconPreset(symbolName: "stethoscope", title: "Doctor", keywords: ["clinic"]),
                CheckInIconPreset(symbolName: "lungs", title: "Breathing", keywords: ["breath"]),
                CheckInIconPreset(symbolName: "brain.head.profile", title: "Mind", keywords: ["mental"]),
                CheckInIconPreset(symbolName: "bed.double", title: "Sleep", keywords: ["rest"]),
                CheckInIconPreset(symbolName: "moon.stars", title: "Night", keywords: ["sleep"]),
                CheckInIconPreset(symbolName: "sun.max", title: "Wake up", keywords: ["morning"])
            ]
        ),
        CheckInIconCategory(
            id: "mind",
            title: "Mind",
            presets: [
                CheckInIconPreset(symbolName: "book.closed", title: "Read", keywords: ["reading"]),
                CheckInIconPreset(symbolName: "book", title: "Book", keywords: ["study"]),
                CheckInIconPreset(symbolName: "graduationcap", title: "Study", keywords: ["learn"]),
                CheckInIconPreset(symbolName: "pencil", title: "Write", keywords: ["journal"]),
                CheckInIconPreset(symbolName: "paintpalette", title: "Creative", keywords: ["art"]),
                CheckInIconPreset(symbolName: "music.note", title: "Music", keywords: ["listen"]),
                CheckInIconPreset(symbolName: "headphones", title: "Listen", keywords: ["audio"]),
                CheckInIconPreset(symbolName: "camera", title: "Photo", keywords: ["capture"]),
                CheckInIconPreset(symbolName: "photo", title: "Image", keywords: ["picture"]),
                CheckInIconPreset(symbolName: "quote.bubble", title: "Reflect", keywords: ["thought"]),
                CheckInIconPreset(symbolName: "lightbulb", title: "Idea", keywords: ["thinking"])
            ]
        ),
        CheckInIconCategory(
            id: "workHome",
            title: "Work & Home",
            presets: [
                CheckInIconPreset(symbolName: "briefcase", title: "Work", keywords: ["job"]),
                CheckInIconPreset(symbolName: "laptopcomputer", title: "Computer", keywords: ["coding"]),
                CheckInIconPreset(symbolName: "keyboard", title: "Typing", keywords: ["write"]),
                CheckInIconPreset(symbolName: "doc.text", title: "Document", keywords: ["paper"]),
                CheckInIconPreset(symbolName: "envelope", title: "Email", keywords: ["mail"]),
                CheckInIconPreset(symbolName: "phone", title: "Call", keywords: ["contact"]),
                CheckInIconPreset(symbolName: "house", title: "Home", keywords: ["family"]),
                CheckInIconPreset(symbolName: "washer", title: "Laundry", keywords: ["clean"]),
                CheckInIconPreset(symbolName: "shower", title: "Shower", keywords: ["wash"]),
                CheckInIconPreset(symbolName: "trash", title: "Trash", keywords: ["clean"]),
                CheckInIconPreset(symbolName: "bag", title: "Errand", keywords: ["shopping"]),
                CheckInIconPreset(symbolName: "gift", title: "Gift", keywords: ["present"]),
                CheckInIconPreset(symbolName: "person.2", title: "Social", keywords: ["people"])
            ]
        )
    ]

    static var allPresets: [CheckInIconPreset] {
        var seen = Set<String>()
        return categories
            .flatMap(\.presets)
            .filter { preset in
                seen.insert(preset.symbolName).inserted
            }
    }

    static func presets(categoryId: String, query: String) -> [CheckInIconPreset] {
        let source: [CheckInIconPreset]
        if categoryId == CheckInIconCategory.allId {
            source = allPresets
        } else {
            source = categories.first { $0.id == categoryId }?.presets ?? allPresets
        }

        let available = source.filter { CheckInSymbolValidator.isValid($0.symbolName) }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return available
        }

        return available.filter { $0.matches(trimmedQuery) }
    }

    static func categoryId(containing symbolName: String) -> String {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.first { category in
            category.presets.contains { $0.symbolName == trimmed }
        }?.id ?? CheckInIconCategory.allId
    }
}
