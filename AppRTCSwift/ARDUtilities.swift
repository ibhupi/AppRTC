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

extension NSDictionary {
    static func dictionaryWith(jsonString: String) -> NSDictionary? {
        assert(jsonString.count > 0)
        guard let data = jsonString.data(using: .utf8) else {
            print("ARDUtilities: dictionary(with jsonString): Could not convert jsonString to type data")
            return nil
        }
        do {
            guard let dict = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.init(rawValue: 0)) as? NSDictionary else {
                print("ARDUtilities: dictionary(with jsonString): Could not convert data to NSDictionary")
                return nil
            }
            return dict
        } catch {
            print("ARDUtilities: dictionary(with jsonString): Error parsing JSON: \(error.localizedDescription)")
            return nil
        }
    }
    
    static func dictionaryWith(jsonData: Data) -> NSDictionary? {
//        let readableData = String(data: jsonData, encoding: String.Encoding.utf8) ?? "Data could not be printed"
//        print("NSDictionary extension: dictionaryWith(jsonData) data: \(readableData))")
        do {
            guard let dict = try JSONSerialization.jsonObject(with: jsonData, options: JSONSerialization.ReadingOptions.init(rawValue: 0)) as? NSDictionary else {
                print("ARDUtilities: dictionary(with jsonString): Could not convert json data to NSDictionary")
                return nil
            }
            return dict
        } catch {
            print("ARDUtilities: dictionary(with jsonData): Error parsing JSON: \(error.localizedDescription)")
            return nil
        }
        
    }
}

extension URLSession {
    class func sendAsyncRequest(request: URLRequest, completionHandler: ((URLResponse?, Data?, Error?) -> ())?) {
        // Kick off an async request which will call back on main thread
        let task = shared.dataTask(with: request) { (data, response, error) in
            guard let completionHandler = completionHandler else {
                return
            }
            completionHandler(response, data, error)
        }
        task.resume()
    }
    
    // Posts data to the specified URL.
    class func sendAsyncPostToURL(url: URL, data: Data?, completionHandler: ((Bool, Data?) -> ())?) {
        print("ARDUtilities: sendAsyncPostToURL: url = \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        sendAsyncRequest(request: request) { (response, data, error) in
            if error != nil {
                print("ARDUtilities: sendAsyncPostToURL: Error posting data: \(String(describing: error?.localizedDescription))")
                guard let completionHandler = completionHandler else {
                    return
                }
                completionHandler(false, data)
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                print("ARDUtilities: sendAsyncPostToURL: did not receive a response")
                return
            }
            guard let data = data else {
                print("ARDUtilities: sendAsyncPostToURL: did not receive data")
                return
            }
            
            if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                let serverResponse = String(data: data, encoding: .utf8)
                print("Received bad response: \(String(describing: serverResponse))")
                guard let completionHandler = completionHandler else {
                    return
                }
                completionHandler(false, data)
                return
            } else {
                guard let completionHandler = completionHandler else {
                    return
                }
                completionHandler(true, data)
                return
            }
        }
    }
}
