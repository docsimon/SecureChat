//
// GlobalState.swift
// SecureChat  
//
// Created by Simone Barbara on 07/10/2025.                               
// All Rights Reserved.                                                         

import SwiftUI

@Observable
final class GlobalState {
    static let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let webSocketURL = URL(string: "wss://echo.websocket.org")!
    static let sqlPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
}
