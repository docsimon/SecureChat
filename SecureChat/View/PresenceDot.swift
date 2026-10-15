//
//  PresenceDot.swift
//  SecureChat
//
//  Green or red next to a contact's name. The relay has no presence, so
//  this is only what this phone has learned on the current connection
//  (session-workflow.md, "Presence"): green while a session is open, red
//  when the last try found them offline or silent, nothing when unknown.
//  Green can be stale: nothing says when they leave.
//

import SwiftUI

enum Presence: Equatable {
    case online
    case offline
}

extension RelayConnection.PeerStatus {
    /// Nil when this says nothing about whether they are there.
    var presence: Presence? {
        switch self {
        case .open: return .online
        case .offline, .unanswered: return .offline
        // Starting is not an answer yet; a session that failed to decrypt
        // says something is wrong, not that they left.
        case .starting, .ended: return nil
        }
    }
}

struct PresenceDot: View {
    let presence: Presence?

    var body: some View {
        if let presence {
            Circle()
                .fill(presence == .online ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityLabel(presence == .online ? "Online" : "Offline")
        }
    }
}
