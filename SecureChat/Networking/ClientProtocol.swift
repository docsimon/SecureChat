//
// ClientProtocol.swift
// SecureChat
//
// Created by Simone Barbara on 09/10/2025.                               
// All Rights Reserved.                                                         

import Foundation

protocol ClientProtocol: AnyObject {
    func send(data: Data) async
    func connect(to: URL) async
    var delegate: ClientDelegate? { get set }
}

protocol ClientDelegate: AnyObject {
    func onReceive(data: Data)
    func onReceive(message: String)
    func onConnectionStatus(status: String)
}
