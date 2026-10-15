//
// DatabaseStrategy.swift
// SecureChat
//
// Created by Simone Barbara on 18/10/2025.
// All Rights Reserved.

import Foundation
import PairingKit

protocol DatabaseStrategy {
    func fetchContacts() throws -> [PairedContact]
    func addContact(_ contact: PairedContact) throws
    /// Oldest first.
    func fetchMessages() throws -> [StoredMessage]
    func addMessage(_ message: StoredMessage) throws
    func updateStatus(of ids: [UUID], to status: StoredMessage.Status) throws
}
