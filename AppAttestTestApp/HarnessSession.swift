//
//  HarnessSession.swift
//  AppAttestTestApp
//
//  Groups events into one attempt at the flow. A session closes when
//  "Reset module state" or "Delete identity key" is tapped — that event
//  becomes the session's last entry, and whatever comes next starts a new
//  session. This is reusable infrastructure, not mock-specific: a real
//  device test involving multiple kill-and-relaunch or reinstall cycles
//  needs exactly this grouping to stay readable.
//

import SwiftUI

struct HarnessSession: Identifiable {
    let id = UUID()
    var events: [HarnessEvent] = []

    var startedAt: Date? { events.map(\.timestamp).min() }

    private var hasFailure: Bool { events.contains { $0.isError } }
    private var isAttested: Bool { events.contains { $0.kind == .attestationStepSubmitted } }
    private var wasClosed: Bool { events.contains { $0.kind == .moduleReset || $0.kind == .identityKeyDeleted } }

    var outcomeLabel: String {
        if hasFailure { return "Failed" }
        if isAttested { return "Attested" }
        if wasClosed { return "Reset before attesting" }
        return "In progress"
    }

    var outcomeSystemImage: String {
        if hasFailure { return "xmark.octagon.fill" }
        if isAttested { return "checkmark.seal.fill" }
        if wasClosed { return "arrow.uturn.backward.circle" }
        return "circle.dashed"
    }

    var outcomeColor: Color {
        if hasFailure { return .red }
        if isAttested { return .green }
        if wasClosed { return .secondary }
        return .accentColor
    }
}
