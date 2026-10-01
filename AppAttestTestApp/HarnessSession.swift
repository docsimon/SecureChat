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

    /// Deliberately NOT "did a signFailed event ever happen" — that was a
    /// real regression found on a real device: a Sign failure followed by a
    /// later SUCCESSFUL retry (the same legitimate "retried and it worked"
    /// story freshlyAttested already tells for attestation) got stuck
    /// permanently flagged, because a sign failure earlier in the array made
    /// `events.contains` true forever, regardless of what happened after.
    /// `events` is already chronological (appended in order by `log()`), so
    /// the LAST matching event in array order is simply the most recent one
    /// — no timestamp comparison needed, and robust to equal timestamps from
    /// fast-succession events.
    private var lastSignOutcomeIsFailure: Bool {
        events.last { $0.kind == .signFailed || $0.kind == .assertionSigned }?.kind == .signFailed
    }

    // Checked in this order deliberately: a session that hit a retryable
    // failure but ultimately succeeded is a SUCCESS story (the retry policy
    // working as designed), not a failure — checking hasFailure first would
    // mislabel exactly the scenario this tool most needs to get right. But
    // lastSignOutcomeIsFailure is checked BEFORE falling back to the retry
    // wording, specifically so a sign failure that's STILL unresolved is
    // never swallowed by that story — one that was later fixed by a
    // successful retry falls through to the normal success wording instead.
    var outcomeLabel: String {
        if freshlyAttested {
            if lastSignOutcomeIsFailure { return "Attested, but a later Sign failed" }
            return hasFailure ? "Attested (after a retry)" : "Attested"
        }
        if restoredAttested {
            if lastSignOutcomeIsFailure { return "Attested (restored), but a later Sign failed" }
            return "Attested (restored)"
        }
        if hasFailure { return "Failed" }
        if wasClosed { return "Reset before attesting" }
        return "In progress"
    }

    var outcomeSystemImage: String {
        if (freshlyAttested || restoredAttested) && lastSignOutcomeIsFailure { return "exclamationmark.triangle.fill" }
        if freshlyAttested || restoredAttested { return "checkmark.seal.fill" }
        if hasFailure { return "xmark.octagon.fill" }
        if wasClosed { return "arrow.uturn.backward.circle" }
        return "circle.dashed"
    }

    var outcomeColor: Color {
        if (freshlyAttested || restoredAttested) && lastSignOutcomeIsFailure { return .orange }
        if freshlyAttested || restoredAttested { return .green }
        if hasFailure { return .red }
        if wasClosed { return .secondary }
        return .accentColor
    }
}
