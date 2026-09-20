//
//  HarnessHistoryDetailView.swift
//  AppAttestTestApp
//

import SwiftUI

struct HarnessHistoryDetailView: View {
    let event: HarnessEvent

    var body: some View {
        List {
            Section {
                LabeledContent("Type", value: event.kind.rawValue)
                LabeledContent("Time", value: event.timestamp.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Result", value: event.isError ? "Failed" : "OK")
                    .foregroundStyle(event.isError ? .red : .primary)
            }
            if !event.detail.isEmpty {
                Section("Details") {
                    ForEach(event.detail) { field in
                        LabeledContent(field.label, value: field.value)
                            .font(.system(.footnote, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }
}
