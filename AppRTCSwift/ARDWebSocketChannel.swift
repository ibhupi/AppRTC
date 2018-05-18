/*
 * libjingle
 * Copyright 2014, Google Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import SocketRocket

enum ARDWebSocketChannelState {
    // State when disconnected.
    case kARDWebSocketChannelStateClosed
    // State when connection is established but not ready for use.
    case kARDWebSocketChannelStateOpen
    // State when connection is established and registered.
    case kARDWebSocketChannelStateRegistered
    // State when connection encounters a fatal error.
    case kARDWebSocketChannelStateError
}

// TODO(tkchin): move these to a configuration object.
let kARDWSSMessageErrorKey = "error";
let kARDWSSMessagePayloadKey = "msg";

protocol ARDWebSocketChannelDelegate: class {
    func channel(channel: ARDWebSocketChannel, didChange state: ARDWebSocketChannelState)
    func channel(channel: ARDWebSocketChannel, didReceive message: ARDSignalingMessage)
}

// Wraps a WebSocket connection to the AppRTC WebSocket server.
class ARDWebSocketChannel: NSObject {
    var roomID: String?
    var clientID: String?
    var state: ARDWebSocketChannelState?
    
    var url: URL
    var restURL: URL
    var socket: SRWebSocket
    var delegate: ARDWebSocketChannelDelegate
    
    init(with url: URL, restURL: URL, delegate: ARDWebSocketChannelDelegate) {
        self.url = url
        self.restURL = restURL
        self.delegate = delegate
        self.socket = SRWebSocket(url: url)
        super.init()
        
        self.socket.delegate = self
        print("ARDWebSocketChannel: init(): Opening WebSocket")
        self.socket.open()
    }
    
    deinit {
        self.disconnect()
    }
    
    func setState(state: ARDWebSocketChannelState) {
        if self.state == state {
            return
        }
        self.state = state
        delegate.channel(channel: self, didChange: state)
    }
    
    // Registers with the WebSocket server for the given room and client id once
    // the web socket connection is open.
    func registerFor(roomID: String, clientID: String) {
        assert(roomID.count > 0)
        assert(clientID.count > 0)
        self.roomID = roomID
        self.clientID = clientID
        if self.state == ARDWebSocketChannelState.kARDWebSocketChannelStateOpen {
            self.registerWithCollider()
        }
    }
    
    // Sends data over the WebSocket connection if registered, otherwise POSTs to
    // the web socket server instead.
    func sendData(data: Data) {
        assert((roomID?.count)! > 0)
        assert((clientID?.count)! > 0)
        if self.state == ARDWebSocketChannelState.kARDWebSocketChannelStateRegistered {
            let payload = String(data: data, encoding: .utf8)
            let message = [
                "cmd": "send",
                "msg": payload
            ]
            var messageJSONObject: Data
            
            do {
                messageJSONObject = try JSONSerialization.data(withJSONObject: message, options: [])
            } catch {
                print("ARDWebSocketChannel: sendData(data): Could not serialize message dictionary to JSON: \(error.localizedDescription)")
                return
            }
            let messageString = String(data: messageJSONObject, encoding: .utf8)
            print("ARDWebSocketChannel: sendData(data): C->WSS: \(messageString ?? ""))")
            socket.send(messageString)
        } else {
            let dataString = String(data: data, encoding: .utf8)
            print("ARDWebSocketChannel: sendData(data): C->WSS POST: \(String(describing: dataString))")
            let urlString = "\(restURL)\(roomID ?? "")\(clientID ?? "")"
            guard let url = URL(string: urlString) else {
                print("ARDWebSocketChannel: sendData(data:): Could not get url")
                return
            }
            URLSession.sendAsyncPostToURL(url: url, data: data, completionHandler: nil)
        }
    }
    
    func disconnect() {
        if state == ARDWebSocketChannelState.kARDWebSocketChannelStateClosed || state == ARDWebSocketChannelState.kARDWebSocketChannelStateError {
            return
        }
        socket.close()
        print("ARDWebSocketChannel: disconnect(): C->WSS DELETE roomID: \(roomID ?? ""), clientID: \(clientID ?? "")")
        let urlString = "\(restURL)\(roomID ?? "")\(clientID ?? "")"
        guard let url = URL(string: urlString) else {
            print("ARDWebSocketChannel: disconnect(): could not get url")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.httpBody = nil
        URLSession.sendAsyncRequest(request: request, completionHandler: nil)
    }
    
    // MARK: - Private
    
    fileprivate func registerWithCollider() {
        if state == ARDWebSocketChannelState.kARDWebSocketChannelStateRegistered {
            return
        }
        guard let roomID = roomID, let clientID = clientID else {
            print("ARDWebSocketChannel: registerWithCollider() roomID and/or clientID are/is not set")
            return
        }
        assert(roomID.count > 0)
        assert(clientID.count > 0)
        let registerMessage = [
            "cmd": "register",
            "roomid": roomID,
            "clientid": clientID
        ]
        
        var message: Data
        do {
            message = try JSONSerialization.data(withJSONObject: registerMessage, options: .prettyPrinted)
        } catch {
            print("ARDWebSocketChannel: registerWithCollider() Could not get data from jsonObject: \(error.localizedDescription)")
            return
        }
        
        guard let messageString = String.init(data: message, encoding: .utf8) else {
            print("ARDWebSocketChannel: registerWithCollider() Could not get messageString from message data")
            return
        }
        print("Registering on WSS for roomID: \(roomID) clientID: \(clientID)")
        // Registration can fail if server rejects it.  For example, if the room is full.
        socket.send(messageString)
        setState(state: .kARDWebSocketChannelStateRegistered)
    }
}

extension ARDWebSocketChannel: SRWebSocketDelegate {
    
    // MARK: - SRWebSocketDelegate
    func webSocketDidOpen(_ webSocket: SRWebSocket!) {
        print("ARDWebSocketChannel: WebSocket connection opened")
        setState(state: .kARDWebSocketChannelStateOpen)
        guard let roomID = roomID, let clientID = clientID else {
            print("ARDWebSocketChannel: webSocketDidOpen(): roomID and/or clientID are/is nil")
            return
        }
        if roomID.count > 0 && clientID.count > 0 {
            self.registerWithCollider()
        }
    }
    
    func webSocket(_ webSocket: SRWebSocket!, didReceiveMessage message: Any!) {
        guard let messageString = message as? String, let messageData = messageString.data(using: .utf8) else {
            print("ARDWebSocketChannel: webSocket(didReceiveMessage): Could not get String from message")
            return
        }
        
        var jsonObject: Any
        
        do {
           jsonObject = try JSONSerialization.jsonObject(with: messageData, options: JSONSerialization.ReadingOptions.init(rawValue: 0))
        } catch {
            print("ARDWebSocketChannel: webSocket(didReceiveMessage): Could not get JSON object from messageData: \(error.localizedDescription)")
            return
        }
        
        guard let wssMessage = jsonObject as? NSDictionary else {
            print("ARDWebSocketChannel: webSocket(didReceiveMessage) could not convert jsonObject to dictionary: \(jsonObject)")
            return
        }
        guard let _ = wssMessage.value(forKey: kARDWSSMessageErrorKey) as? String else {
            print("ARDWebSocketChannel: webSocket(didReceiveMessage) WSS error: \(wssMessage.value(forKey: kARDWSSMessageErrorKey) ?? "")")
            return
        }
        guard let payload = wssMessage.value(forKey: kARDWSSMessagePayloadKey) as? String,
            let signalingMessage = ARDSignalingMessage.messageFrom(jsonString: payload) else {
            print("ARDWebSocketChannel: webSocket(didReceiveMessage) could not get payload and assign to signaling message")
            return
        }
        
        print("ARDWebSocketChannel: webSocket(didReceiveMessage) WSS->C: \(payload)")
        delegate.channel(channel: self, didReceive: signalingMessage)
    }
    
    func webSocket(_ webSocket: SRWebSocket!, didFailWithError error: Error!) {
        print("ARDWebSocketChannel: webSocket(didReceiveMessage) WebSocket error: \(error)")
        setState(state: .kARDWebSocketChannelStateError)
    }
    
    func webSocket(_ webSocket: SRWebSocket!, didCloseWithCode code: Int, reason: String!, wasClean: Bool) {
        print("ARDWebSocketChannel: webSocket(didReceiveMessage) WebSocket closed with code \(code) reason: \(reason), wasClean: \(wasClean)")
        assert(state != ARDWebSocketChannelState.kARDWebSocketChannelStateError)
        setState(state: .kARDWebSocketChannelStateClosed)
    }
}
