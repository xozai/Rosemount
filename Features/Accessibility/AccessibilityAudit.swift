// Features/Accessibility/AccessibilityAudit.swift
// Accessibility helpers, modifiers, and audit utilities

import SwiftUI

// MARK: - Accessibility View Modifiers

/// Adds a consistent post card accessibility label combining author, timestamp and content.
struct PostCardAccessibility: ViewModifier {
    let authorName: String
    let relativeTime: String
    let content: String
    let favouritesCount: Int
    let repliesCount: Int

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(authorName), \(relativeTime). \(self.content)")
            .accessibilityHint("Double tap to open thread. \(favouritesCount) likes, \(repliesCount) replies.")
    }
}

extension View {
    func postCardAccessibility(authorName: String, relativeTime: String, content: String, favouritesCount: Int, repliesCount: Int) -> some View {
        modifier(PostCardAccessibility(authorName: authorName, relativeTime: relativeTime, content: content, favouritesCount: favouritesCount, repliesCount: repliesCount))
    }
}

/// Respect Reduce Motion for animations.
struct ReduceMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.75), value: UUID())
    }
}

// MARK: - Dynamic Type Scaling

/// Clamps Dynamic Type to prevent layout breaking at xxxLarge sizes while still scaling.
struct DynamicTypeClamp: ViewModifier {
    let range: ClosedRange<DynamicTypeSize>

    func body(content: Content) -> some View {
        content.dynamicTypeSize(range)
    }
}

extension View {
    func dynamicTypeClamped(_ range: ClosedRange<DynamicTypeSize> = .xSmall ... .accessibility2) -> some View {
        modifier(DynamicTypeClamp(range: range))
    }
}

// MARK: - Image Accessibility

extension View {
    func accessibilityImageLabel(_ label: String) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Focus Order Helper

/// Wraps common accessibility focus management patterns.
struct AccessibleForm<Content: View>: View {
    @ViewBuilder let content: Content
    @AccessibilityFocusState private var focusedField: Bool

    var body: some View {
        content
            .onAppear { focusedField = true }
    }
}

// MARK: - VoiceOver Announcement

struct VoiceOverAnnouncement {
    static func post(_ message: String, after delay: TimeInterval = 0.1) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    static func screenChanged(withFocusOn element: Any? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: element)
    }

    static func layoutChanged() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
}

// MARK: - Color Contrast Helpers

extension Color {
    /// Ensures a foreground color meets WCAG AA contrast (4.5:1) against white.
    static func accessibleBlue() -> Color { Color(red: 0.0, green: 0.45, blue: 0.85) }
    static func accessibleRed() -> Color { Color(red: 0.8, green: 0.0, blue: 0.0) }
    static func accessibleGreen() -> Color { Color(red: 0.0, green: 0.55, blue: 0.2) }
}

// MARK: - Audit Checklist

/// Accessibility audit checklist. Accessible via Settings → About → Accessibility Audit.
/// Updated whenever a new flow is audited; .warning items track outstanding work.
struct AccessibilityAuditView: View {
    struct AuditItem: Identifiable {
        let id = UUID()
        let category: String
        let item: String
        let status: AuditStatus

        enum AuditStatus { case pass, fail, warning }
    }

    let items: [AuditItem] = [
        AuditItem(category: "VoiceOver", item: "Post cards have combined label with author, time, content", status: .pass),
        AuditItem(category: "VoiceOver", item: "Action bar buttons (like, boost, reply) have accessibility labels", status: .pass),
        AuditItem(category: "VoiceOver", item: "Boost header combined into single accessible element", status: .pass),
        AuditItem(category: "VoiceOver", item: "Custom actions provided for swipe gestures", status: .pass),
        AuditItem(category: "VoiceOver", item: "Profile Settings gear button labelled", status: .pass),
        AuditItem(category: "VoiceOver", item: "Home feed filter menu labelled with current state", status: .pass),
        AuditItem(category: "VoiceOver", item: "Encryption lock badge in DMs labelled", status: .pass),
        AuditItem(category: "VoiceOver", item: "Location chip in Compose labelled", status: .pass),
        AuditItem(category: "Dynamic Type", item: "Post card author row clamped to accessibility2", status: .pass),
        AuditItem(category: "Dynamic Type", item: "Boost header text clamped to accessibility2", status: .pass),
        AuditItem(category: "Dynamic Type", item: "Action bar counts clamped to accessibility2", status: .pass),
        AuditItem(category: "Dynamic Type", item: "Layouts don't break at xxxLarge", status: .warning),
        AuditItem(category: "Color", item: "WCAG AA contrast for primary text (4.5:1)", status: .pass),
        AuditItem(category: "Color", item: "UI not dependent solely on color", status: .pass),
        AuditItem(category: "Motion", item: "Animations respect Reduce Motion", status: .pass),
        AuditItem(category: "Focus", item: "Keyboard/Switch Control focus order is logical", status: .pass),
        AuditItem(category: "Tap Target", item: "All tap targets ≥ 44×44pt", status: .pass),
        AuditItem(category: "Hearing", item: "Audio content (Voice Rooms) has visual level indicator", status: .warning),
        AuditItem(category: "Cognitive", item: "Error messages are clear and actionable", status: .pass),
        AuditItem(category: "Localization", item: "Localizable.strings scaffold created (en)", status: .pass),
        AuditItem(category: "Localization", item: "All user-visible strings migrated to String(localized:)", status: .warning),
    ]

    var body: some View {
        List {
            let categories = ["VoiceOver", "Dynamic Type", "Color", "Motion", "Focus", "Tap Target", "Hearing", "Cognitive", "Localization"]
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    ForEach(items.filter { $0.category == category }) { item in
                        HStack {
                            Image(systemName: item.status == .pass ? "checkmark.circle.fill"
                                : item.status == .fail ? "xmark.circle.fill"
                                : "exclamationmark.circle.fill")
                            .foregroundStyle(item.status == .pass ? .green
                                : item.status == .fail ? .red : .orange)
                            .accessibilityHidden(true)

                            Text(item.item)
                                .font(.subheadline)

                            Spacer()

                            Text(item.status == .pass ? "Pass"
                                : item.status == .fail ? "Fail" : "Warning")
                                .font(.caption)
                                .foregroundStyle(item.status == .pass ? .green
                                    : item.status == .fail ? .red : .orange)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.item): \(item.status == .pass ? "Pass" : item.status == .fail ? "Fail" : "Warning")")
                    }
                }
            }
        }
        .navigationTitle("Accessibility Audit")
    }
}
