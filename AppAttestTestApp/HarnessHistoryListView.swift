//
//  HarnessHistoryListView.swift
//  AppAttestTestApp
//

import SwiftUI

struct HarnessHistoryListView: View {
    let events: [HarnessEvent]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "clock",
                    description: Text("Run through the steps to populate history."))
            } else {
                List(events) { event in
                    NavigationLink(destination: HarnessHistoryDetailView(event: event)) {
                        row(for: event)
                    }
                }
            }
        }
        .navigationTitle("History")
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
