//
//  MockTransport.swift
//  AppAttestKitTests
//
//  Test double for `AttestationTransport`. The real implementation talks to
//  the app's own server; the module must never know a URL (module doc §3),
//  so this is the only transport it ever sees in tests.
//

import Foundation
@testable import AppAttestKit

/// Actor, same reasoning as the other mocks — both protocol methods are async.
actor MockTransport: AttestationTransport {

    private(set) var fetchChallengeCallCount = 0
    private(set) var submittedRequests: [AttestationSubmission] = []

    private var fetchChallengeResults: [Result<Data, Error>]
    private var submitResults: [Result<String, Error>]

    init(fetchChallengeResults: [Result<Data, Error>] = [.success(Data([0xAA, 0xBB]))],
         submitResults: [Result<String, Error>] = [.success("account-uuid")]) {
        self.fetchChallengeResults = fetchChallengeResults
        self.submitResults = submitResults
    }

    func fetchChallenge() async throws -> Data {
        fetchChallengeCallCount += 1
        return try consume(&fetchChallengeResults)
    }

    func submitAttestation(_ request: AttestationSubmission) async throws -> String {
        submittedRequests.append(request)
        return try consume(&submitResults)
    }

    private func consume<T>(_ queue: inout [Result<T, Error>]) throws -> T {
        precondition(!queue.isEmpty, "MockTransport: no result queued for this call")
        let result = queue.count > 1 ? queue.removeFirst() : queue[0]
        return try result.get()
    }
}
