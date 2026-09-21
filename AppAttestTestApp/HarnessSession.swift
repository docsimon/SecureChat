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
    /// A fresh attestation actually completed within this session.
    private var freshlyAttested: Bool { events.contains { $0.kind == .attestationStepSubmitted } }
    /// No fresh attestation ran in this session — it was recognized as
    /// already-attested purely via restore() on launch. Distinct from
    /// freshlyAttested so the label can say which one happened; without
    /// this, a session that only ever restored (e.g. after a plain kill and
    /// relaunch) has no event proving success and falls through to
    /// "In progress" even though nothing is actually pending.
    private var restoredAttested: Bool {
        events.contains { event in
            guard event.kind == .restored else { return false }
            return event.detail.contains { $0.label == "Restored as attested" && $0.value == "yes" }
        }
    }
    private var wasClosed: Bool { events.contains { $0.kind == .moduleReset || $0.kind == .identityKeyDeleted } }

    // Checked in this order deliberately: a session that hit a retryable
    // failure but ultimately succeeded is a SUCCESS story (the retry policy
    // working as designed), not a failure — checking hasFailure first would
    // mislabel exactly the scenario this tool most needs to get right.
    var outcomeLabel: String {
        if freshlyAttested { return hasFailure ? "Attested (after a retry)" : "Attested" }
        if restoredAttested { return "Attested (restored)" }
        if hasFailure { return "Failed" }
        if wasClosed { return "Reset before attesting" }
        return "In progress"
    }

    var outcomeSystemImage: String {
        if freshlyAttested || restoredAttested { return "checkmark.seal.fill" }
        if hasFailure { return "xmark.octagon.fill" }
        if wasClosed { return "arrow.uturn.backward.circle" }
        return "circle.dashed"
    }

    var outcomeColor: Color {
        if freshlyAttested || restoredAttested { return .green }
        if hasFailure { return .red }
        if wasClosed { return .secondary }
        return .accentColor
    }
}
