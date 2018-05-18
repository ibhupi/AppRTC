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

let kRTCICEServerUsernameKey = "username"
let kRTCICEServerPasswordKey = "password"
let kRTCICEServerUrisKey = "uris"
let kRTCICEServerUrlKey = "urls"
let kRTCICEServerCredentialKey = "credential"

extension RTCICEServer {

    class func serverFrom(jsonDictionary: [String: Any]) -> RTCICEServer {
        let url = jsonDictionary[kRTCICEServerUrlKey] as? String ?? ""
        let username = jsonDictionary[kRTCICEServerUsernameKey] as? String ?? ""
        let credential = jsonDictionary[kRTCICEServerCredentialKey] as? String ?? ""
        
        return RTCICEServer(uri: URL(string: url), username: username, password: credential)
    }
    
    // CEOD provides different JSON, and this parses that.
    class func serversFromCEOD(jsonDictionary: [String: Any]) -> [RTCICEServer] {
        let username = jsonDictionary[kRTCICEServerUsernameKey] as? String ?? ""
        let password = jsonDictionary[kRTCICEServerPasswordKey] as? String ?? ""
        let uris = jsonDictionary[kRTCICEServerUrisKey] as? [String] ?? [""]
        var servers = [RTCICEServer]()
        
        for uri in uris {
            if let server = RTCICEServer(uri: URL(string: uri), username: username, password: password) {
                servers.append(server)
            }
        }
        return servers
    }
}
