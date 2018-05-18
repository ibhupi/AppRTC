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

enum ARDSignalingMessageType {
    case kARDSignalingMessageTypeCandidate
    case kARDSignalingMessageTypeOffer
    case kARDSignalingMessageTypeAnswer
    case kARDSignalingMessageTypeBye
}

let kARDSignalingMessageTypeKey = "type"

class ARDSignalingMessage: NSObject {
    var type: ARDSignalingMessageType?
    
    init(with type: ARDSignalingMessageType) {
        super.init()
        self.type = type
    }
    
    private func description() -> String? {
        guard let data = JSONData() else {
            print("ARDSignalingMessage: description(): Could not retrieve data from JSONData()")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    class func messageFrom(jsonString: String) -> ARDSignalingMessage? {
        guard let values = NSDictionary.dictionaryWith(jsonString: jsonString) as? [String: Any] else {
            print("ARDSignalingMessage: messageFrom(jsonString): could not get dictionary with jsonString as type [String: Any]")
            return nil
        }
        guard let typeString = values[kARDSignalingMessageTypeKey] as? String else {
            print("ARDSignalingMessage: messageFrom(jsonString): could not retrieve values[kARDSignalingMessageTypeKey] as String")
            return nil
        }
        
        var message: ARDSignalingMessage?
        
        if typeString == "candidate" {
            let candidate = RTCICECandidate.candidate(from: values)
            message = ARDICECandidateMessage.init(with: candidate)
        } else if typeString == "offer" || typeString == "answer" {
            if let description = RTCSessionDescription.description(from: values) {
                message = ARDSessionDescriptionMessage.init(with: description)
            }
        } else if typeString == "bye" {
            message = ARDByeMessage()
        } else {
            print("ARDSignalingMessage: messageFrom(jsonString): Unexpected type: \(typeString)")
        }
        return message
    }
    
    func JSONData() -> Data? {
        return nil
    }
}

class ARDICECandidateMessage: ARDSignalingMessage {
    var candidate: RTCICECandidate?
    
    init(with candidate: RTCICECandidate) {
        super.init(with: ARDSignalingMessageType.kARDSignalingMessageTypeCandidate)
        self.candidate = candidate
    }
    
    override func JSONData() -> Data? {
        return candidate?.JSONData()
    }
}

class ARDSessionDescriptionMessage: ARDSignalingMessage {
    var sessionDescription: RTCSessionDescription?
    
    init(with description: RTCSessionDescription) {
        var type = ARDSignalingMessageType.kARDSignalingMessageTypeOffer
        let typeString = description.type
        if typeString == "offer" {
            type = ARDSignalingMessageType.kARDSignalingMessageTypeOffer
        } else if typeString == "answer" {
            type = ARDSignalingMessageType.kARDSignalingMessageTypeAnswer
        } else {
            assert(false, "ARDSessionDescriptionMessage: init(with description): Unexpected type: \(String(describing: typeString))")
        }
        super.init(with: type)
        sessionDescription = description
    }
    
    override func JSONData() -> Data? {
        return sessionDescription?.JSONData()
    }
}

class ARDByeMessage: ARDSignalingMessage {
    init() {
        super.init(with: ARDSignalingMessageType.kARDSignalingMessageTypeBye)
    }
    
    override func JSONData() -> Data? {
        let message = ["type": "bye"]
        do {
            return try JSONSerialization.data(withJSONObject: message, options: .prettyPrinted)
        } catch {
            print("ARDByeMessage: JSONData(): Could not get json data from message data: \(error.localizedDescription)")
            return nil
        }
    }
}
