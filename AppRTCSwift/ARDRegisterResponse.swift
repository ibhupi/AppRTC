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

enum ARDRegisterResultType {
    case kARDRegisterResultTypeUnknown
    case kARDRegisterResultTypeSuccess
    case kARDRegisterResultTypeFull
}

let kARDRegisterResultKey = "result";
let kARDRegisterResultParamsKey = "params";
let kARDRegisterInitiatorKey = "is_initiator";
let kARDRegisterRoomIdKey = "room_id";
let kARDRegisterClientIdKey = "client_id";
let kARDRegisterMessagesKey = "messages";
let kARDRegisterWebSocketURLKey = "wss_url";
let kARDRegisterWebSocketRestURLKey = "wss_post_url";

// Result of registering with the GAE server.
class ARDRegisterResponse: NSObject {
    var result: ARDRegisterResultType?
    var isInitiator: Bool?
    var roomID: String?
    var clientID: String?
    var messages: NSArray?
    var webSocketURL: URL?
    var webSocketRestURL: URL?
    
    class func responseFrom(jsonData: Data) -> ARDRegisterResponse? {
        guard let responseJSON = NSDictionary.dictionaryWith(jsonData: jsonData),
            let resultString = responseJSON[kARDRegisterResultKey] as? String,
            let params = responseJSON.value(forKey: kARDRegisterResultParamsKey) as? NSDictionary else {
            print("ARDRegisterResponse: responseFrom(jsonData): could not get a dictionary from json data, and/or string, or params from json response")
            return nil
        }
        guard let isInitiator = params.value(forKey: kARDRegisterInitiatorKey) as? String,
            let roomID = params.value(forKey: kARDRegisterRoomIdKey) as? String,
            let clientID = params.value(forKey: kARDRegisterClientIdKey) as? String,
            let messages = params[kARDRegisterMessagesKey] as? NSArray else {
                print("ARDRegisterResponse: responseFrom(jsonData): could not get isInitiator, roomID, clientID, and/or messages from params NSDictionary")
                return nil
        }
        
        let response = ARDRegisterResponse()
        response.result = ARDRegisterResponse.resultTypeFromString(resultString: resultString)
        response.isInitiator = isInitiator == "false" ? false : true
        response.roomID = roomID
        response.clientID = clientID
        
        // Parse messages.
        var signalingMessages: [ARDSignalingMessage] = []
        for message in messages {
            if let msg = message as? String {
                let signalingMessage = ARDSignalingMessage.messageFrom(jsonString: msg)
                // Add non nil signaling message
                if let signalingMsg = signalingMessage {
                    signalingMessages.append(signalingMsg)
                }
            }
        }
        // Error parsing signaling message JSON
        if messages.count > 0 && signalingMessages.count == 0 {
            response.result = ARDRegisterResultType.kARDRegisterResultTypeUnknown
        }
        response.messages = signalingMessages as NSArray?
        
        // Parse websocket urls
        guard let webSocketURLString = params[kARDRegisterWebSocketURLKey] as? String,
            let webSocketRestURLString = params[kARDRegisterWebSocketRestURLKey] as? String else {
                print("ARDRegisterResponse: responseFrom(jsonData): could not get websocket urls from params NSDictionary")
                return nil
        }
        response.webSocketURL = URL(string: webSocketURLString)
        response.webSocketRestURL = URL(string: webSocketRestURLString)
        
        return response
    }
    
    // Private
    private class func resultTypeFromString(resultString: String) -> ARDRegisterResultType {
        var result = ARDRegisterResultType.kARDRegisterResultTypeUnknown
        if resultString == "SUCCESS" {
            result = ARDRegisterResultType.kARDRegisterResultTypeSuccess
        } else if resultString == "FULL" {
            result = ARDRegisterResultType.kARDRegisterResultTypeFull
        }
        return result
    }

}
