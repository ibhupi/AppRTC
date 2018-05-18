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

enum ARDMessageResultType {
    case kARDMessageResultTypeUnknown
    case kARDMessageResultTypeSuccess
    case kARDMessageResultTypeInvalidRoom
    case kARDMessageResultTypeInvalidClient
}

let kARDMessageResultKey = "result"

class ARDMessageResponse : NSObject {
    
    var result: ARDMessageResultType?

    class func responseFrom(jsonData: Data) -> ARDMessageResponse? {
        guard let responseJSON = NSDictionary.dictionaryWith(jsonData: jsonData) else {
            print("ARDMessageResponse: responseFrom(jsonData): Could not get a response dictionary")
            return nil
        }
        
        guard let resultString = responseJSON.value(forKey: kARDMessageResultKey) as? String else {
            print("ARDMessageResponse: responseFrom(jsonData): Could not get value as String type from result key")
            return nil
        }
        
        let response = ARDMessageResponse()
        response.result = ARDMessageResponse.resultTypeFromString(resultString: resultString)
        return response
    }
    
    // MARK: - Private
    private class func resultTypeFromString(resultString: String) -> ARDMessageResultType {
        var result = ARDMessageResultType.kARDMessageResultTypeUnknown
        if resultString == "SUCCESS" {
            result = ARDMessageResultType.kARDMessageResultTypeSuccess
        } else if resultString == "INVALID_CLIENT" {
            result = ARDMessageResultType.kARDMessageResultTypeInvalidClient
        } else if resultString == "INVALID_ROOM" {
            result = ARDMessageResultType.kARDMessageResultTypeInvalidRoom
        }
        return result
    }
}
