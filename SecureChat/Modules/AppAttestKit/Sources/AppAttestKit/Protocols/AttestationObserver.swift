//
//  AttestationObserver.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 02/09/2026.
//

import Foundation

/// Passive notification sink. The coordinator calls it; the module does nothing
/// with the calls. The app decides whether that means logging or analytics.
///
/// DO NOT drive UI from this — it fires from actor context and would need an
/// explicit MainActor hop. Have the view model read coordinator state instead.
public protocol AttestationObserver: Sendable {
    func didTransition(to state: AttestationState)
    func didFail(_ error: AttestationError, attempt: Int)
}
