//
//  HarnessHistoryListView.swift
//  AppAttestTestApp
//
//  Top-level history screen: one row per attempt (session), not one row per
//  step — drill into a session for its chronological trace.
//

import SwiftUI

struct HarnessHistoryListView: View {
    let sessions: [HarnessSession]

    /// (originalNumber, session) pairs, non-empty only, newest attempt
    /// first — a run-history convention, unlike the chronological
    /// oldest-first ordering used *within* a session's own trace.
    private var numberedSessions: [(number: Int, session: HarnessSession)] {
        Array(sessions.enumerated())
            .filter { !$0.element.events.isEmpty }
            .map { (number: $0.offset + 1, session: $0.element) }
            .reversed()
    }

    var body: some View {
        Group {
            if numberedSessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "clock",
                    description: Text("Run through the steps to start one."))
            } else {
                List(numberedSessions, id: \.session.id) { entry in
                    NavigationLink(destination: HarnessSessionDetailView(session: entry.session, number: entry.number)) {
                        row(for: entry.session, number: entry.number)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }

    private func row(for session: HarnessSession, number: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.outcomeSystemImage)
                .foregroundStyle(session.outcomeColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Session \(number)").font(.subheadline).bold()
                Text(session.outcomeLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let started = session.startedAt {
                    Text(started.formatted(date: .omitted, time: .standard))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text("\(session.events.count) events")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
