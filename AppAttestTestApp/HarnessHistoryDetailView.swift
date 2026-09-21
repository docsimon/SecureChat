//
//  HarnessHistoryDetailView.swift
//  AppAttestTestApp
//

import SwiftUI
import UIKit

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
                        if field.value.count > 60 {
                            longValueRow(field)
                        } else {
                            LabeledContent(field.label, value: field.value)
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
            }
        }
        .navigationTitle("Event")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Long values (the raw CBOR hex dump, mainly) get their own row: full
    /// width, wrapped to a byte-aligned grid rather than SwiftUI's default
    /// arbitrary wrap point, with a copy button so it can be pasted straight
    /// into an external CBOR decoder for independent verification.
    private func longValueRow(_ field: DetailField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.label).font(.subheadline).bold()
                Spacer()
                Button {
                    UIPasteboard.general.string = field.value
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(hexWrapped(field.value))
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    /// Purely a display concern — inserts a newline every 32 hex characters
    /// (16 bytes) for a byte-aligned look. The copy button above copies
    /// `field.value` directly, unwrapped, so pasting into a decoder isn't
    /// affected by this formatting.
    private func hexWrapped(_ hex: String, every: Int = 32) -> String {
        guard hex.count > every else { return hex }
        var result = ""
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: every, limitedBy: hex.endIndex) ?? hex.endIndex
            result += hex[index..<end]
            if end != hex.endIndex { result += "\n" }
            index = end
        }
        return result
    }
}
