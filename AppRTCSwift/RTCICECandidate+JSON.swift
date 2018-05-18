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

let kRTCICECandidateTypeKey = "type";
let kRTCICECandidateTypeValue = "candidate";
let kRTCICECandidateMidKey = "id";
let kRTCICECandidateMLineIndexKey = "label";
let kRTCICECandidateSdpKey = "candidate";

extension RTCICECandidate {
    class func candidate(from jsonDictionary: [String: Any]) -> RTCICECandidate {
        guard let mid = jsonDictionary[kRTCICECandidateMidKey] as? String,
            let sdp = jsonDictionary[kRTCICECandidateSdpKey] as? String,
            let mLineIndex = jsonDictionary[kRTCICECandidateMLineIndexKey] as? Int else {
              print("RTCICECandidate extension: candidate(from jsonDictionary): Could not get mid, sdp, and/or mLineIndex")
                return RTCICECandidate(mid: "", index: 0, sdp: "")
        }
        return RTCICECandidate(mid: mid, index: mLineIndex, sdp: sdp)
    }
    
    func JSONData() -> Data? {
        let json = [
            kRTCICECandidateTypeKey : kRTCICECandidateTypeValue,
            kRTCICECandidateMLineIndexKey : self.sdpMLineIndex,
            kRTCICECandidateMidKey : self.sdpMid,
            kRTCICECandidateSdpKey : self.sdp
        ] as [String: Any]
        
        var data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: json, options: [])
        } catch {
            print("RTCICECandidate extension: JSONData: Could not convert json to type data: \(error.localizedDescription)")
            return nil
        }
        return data
    }
}
