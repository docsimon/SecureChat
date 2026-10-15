//
//  PairingStartScreen.swift
//  PairingKit
//
//  Pairing, screen 1: what to do, how the last attempt ended, and "Pair".
//  All the words live here, so it scrolls at any text size and the code
//  screen can be only the code.
//

import SwiftUI
import UIKit

struct PairingStartScreen: View {

    let outcome: PairingOutcome?
    let cameraDenied: Bool
    let canPair: Bool
    let pair: () -> Void
    /// Debug builds only.
    let showDebug: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Pair with someone next to you")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    step(1, "You both tap Pair.")
                    step(2, "Hold the phones screen to screen, a hand's width apart.")
                    step(3, "Keep them together until you feel a long vibration.")
                }

                if let outcome {
                    OutcomeLine(outcome: outcome)
                }

                if cameraDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SecureChat needs the camera to read the other phone's code.")
                            .foregroundStyle(.secondary)
                        Button("Allow camera") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }

                Button(action: pair) {
                    Text("Pair")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canPair)

                if let showDebug {
                    Button("Debug", action: showDebug)
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OutcomeLine: View {
    let outcome: PairingOutcome

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.headline)
        .foregroundStyle(color)
    }

    private var text: String {
        switch outcome {
        case .paired(let name):
            return "Paired with \(name)."
        case .timedOut(let name):
            return "Pairing with \(name) didn't finish. Try again, and keep the phones together until both vibrate."
        case .nothingRead:
            return "The other phone's code wasn't read. Try again, or switch to the rear camera on the code screen."
        case .refused(let error):
            return PairingSignal.message(for: error)
        }
    }

    private var symbol: String {
        switch outcome {
        case .paired: return "checkmark.circle.fill"
        case .timedOut, .nothingRead: return "exclamationmark.circle.fill"
        case .refused: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch outcome {
        case .paired: return .green
        case .timedOut, .nothingRead: return .orange
        case .refused: return .red
        }
    }
}
