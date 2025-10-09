//
// WebsocketClient.swift
// SecureChat  
//
// Created by Simone Barbara on 09/10/2025.                               
// All Rights Reserved.                                                         

import Foundation

final class WebsocketClient: ClientProtocol {

    weak var delegate: ClientDelegate?
    let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiving = false
    
    init(session: URLSession = URLSession.shared) {
        self.session = session
    }
    
    //MARK: ClientProtocol
    func send(data: Data) async {
        let msg = URLSessionWebSocketTask.Message.data(data)
        task?.send(msg) { error in
            if let error = error {
                print("Error sending the message", error)
            }
        }
        receive()
    }
    
    func connect(to url: URL = URL(string: "wss://echo.websocket.org")!) async {
        task = session.webSocketTask(with: url)
        task?.resume()
        delegate?.onConnectionStatus(status: "Connection status \(String(describing: task?.state))")
        receive()
    }
    
    private func receive() {
        
        guard receiving == false, task?.state == .running else {
            //TODO: Add retrying logic here
            return
        }

        receiving  = true
        task?.receive { result in
            
            switch result {
            case .success(let message):
                if case .data(let data) = message {
                    self.delegate?.onReceive(data: data)
                    print("Received message from server:", String(data: data, encoding: .utf8) ?? "No data")
                } else if case .string(let msg) = message {
                    self.delegate?.onReceive(message: msg)
                }
                //print("Received message", message)
            case .failure(let error):
                print("Error: ", error)
                //self.task?.cancel()
                //self.task = nil
                //print("Error receiving, is task cancelled:")
                //self.printTaskState(state: self.task?.state)
                //sleep(1)
                self.delegate?.onConnectionStatus(status: "Error receiving data \(String(describing: self.task?.state))")
            }
            self.receiving = false
            self.receive()
        }
    }
}
