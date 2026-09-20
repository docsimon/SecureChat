//
//  StepRow.swift
//  AppAttestTestApp
//
//  A single step in the guided sequence — numbered while locked/available,
//  checked once done, spinning while in progress. Shared between the mock
//  preview and (once approved) the real flow, so this doesn't get rebuilt
//  twice.
//

import SwiftUI

struct StepRow: View {
    enum State { case locked, available, inProgress, done }

    let number: Int
    let title: String
    var subtitle: String? = nil
    let state: State
    var isRepeatable: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(state == .locked ? .secondary : .primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if state == .inProgress {
                    ProgressView()
                } else if state == .available || (state == .done && isRepeatable) {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(state == .locked || state == .inProgress || (state == .done && !isRepeatable))
    }

    @ViewBuilder
    private var indicator: some View {
        if state == .done && !isRepeatable {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
        } else {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .frame(width: 28, height: 28)
                .background(Circle().fill(state == .locked ? Color.secondary.opacity(0.3) : Color.accentColor))
                .foregroundStyle(.white)
        }
    }

    private var background: Color {
        switch state {
        case .locked, .available: return Color(uiColor: .secondarySystemBackground)
        case .inProgress: return Color.accentColor.opacity(0.12)
        case .done: return Color.green.opacity(0.10)
        }
    }
}
