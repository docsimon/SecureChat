//
// DatabaseStrategy.swift
// SecureChat
//
// Created by Simone Barbara on 18/10/2025.
// All Rights Reserved.

import Foundation
import PairingKit

/// A message as the database holds it: the text sealed with the contact's
/// key (`MessageSeal`); who, when and the status in the clear.
struct SealedMessage: Equatable {
    let id: UUID
    let peer: UUID
    let sealedText: Data
    let date: Date
    let status: StoredMessage.Status
}

protocol DatabaseStrategy {
    func fetchContacts() throws -> [PairedContact]
    func addContact(_ contact: PairedContact) throws
    /// Oldest first.
    func fetchMessages() throws -> [SealedMessage]
    func addMessage(_ message: SealedMessage) throws
    /// All or none, in one write to disk.
    func addMessages(_ messages: [SealedMessage]) throws
    func updateStatus(of ids: [UUID], to status: StoredMessage.Status) throws
    func deleteMessages(with peer: UUID) throws
    /// Messages stored in plain text by builds before storage option B,
    /// waiting to be sealed. Empty once `dropPlaintextMessages` ran.
    func plaintextMessages() throws -> [StoredMessage]
    /// Removes them and rewrites the file, so no plaintext stays behind in
    /// free pages.
    func dropPlaintextMessages() throws
}
