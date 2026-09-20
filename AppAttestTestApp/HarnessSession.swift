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

    // Checked in this order deliberately: a session that hit a retryable
    // failure but ultimately succeeded is a SUCCESS story (the retry policy
    // working as designed), not a failure — checking hasFailure first would
    // mislabel exactly the scenario this tool most needs to get right.
    var outcomeLabel: String {
        if isAttested { return hasFailure ? "Attested (after a retry)" : "Attested" }
        if hasFailure { return "Failed" }
        if wasClosed { return "Reset before attesting" }
        return "In progress"
    }

    var outcomeSystemImage: String {
        if isAttested { return "checkmark.seal.fill" }
        if hasFailure { return "xmark.octagon.fill" }
        if wasClosed { return "arrow.uturn.backward.circle" }
        return "circle.dashed"
    }

    var outcomeColor: Color {
        if isAttested { return .green }
        if hasFailure { return .red }
        if wasClosed { return .secondary }
        return .accentColor
    }
}
