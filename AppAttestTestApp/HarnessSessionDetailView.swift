//
//  HarnessSessionDetailView.swift
//  AppAttestTestApp
//
//  One session's chronological trace — this is what HarnessHistoryListView
//  used to show directly, before sessions existed as a grouping concept.
//

import SwiftUI

struct HarnessSessionDetailView: View {
    let session: HarnessSession
    let number: Int

    /// Chronological within the session — a trace read top-to-bottom as it
    /// happened, unlike the newest-first convention used for the outer
    /// session list.
    private var sortedEvents: [HarnessEvent] {
        session.events.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        List(sortedEvents) { event in
            NavigationLink(destination: HarnessHistoryDetailView(event: event)) {
                row(for: event)
            }
        }
        .navigationTitle("Session \(number)")
    }

    private func row(for event: HarnessEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.systemImage)
                .foregroundStyle(event.isError ? .red : .accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.rawValue).font(.subheadline).bold()
                Text(event.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
