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
import AVFoundation

// TODO(tkchin): move these to a configuration object.
let kARDRoomServerHostUrl = "https://apprtc.appspot.com"
let kARDRoomServerRegisterFormat = "%@/join/%@"
let kARDRoomServerMessageFormat = "%@/message/%@/%@"
let kARDRoomServerByeFormat = "%@/leave/%@/%@"

let kARDDefaultSTUNServerUrl = "stun:stun.l.google.com:19302";
// TODO(tkchin): figure out a better username for CEOD statistics.
let kARDTurnRequestUrl = "https://computeengineondemand.appspot.com/turn?username=iapprtc&key=4080218913"

let kARDAppClientErrorDomain = "ARDAppClient";
let kARDAppClientErrorUnknown = -1;
let kARDAppClientErrorRoomFull = -2;
let kARDAppClientErrorCreateSDP = -3;
let kARDAppClientErrorSetSDP = -4;
let kARDAppClientErrorNetwork = -5;
let kARDAppClientErrorInvalidClient = -6;
let kARDAppClientErrorInvalidRoom = -7;

enum ARDAppClientState {
    // Disconnected from servers.
    case kARDAppClientStateDisconnected
    // Connecting to servers.
    case kARDAppClientStateConnecting
    // Connected to servers.
    case kARDAppClientStateConnected
}

protocol ARDAppClientDelegate: class {
    func appClient(client: ARDAppClient, didChange state: ARDAppClientState)
    func appClient(client: ARDAppClient, didReceiveLocal videoTrack: RTCVideoTrack)
    func appClient(client: ARDAppClient, didReceiveRemote videoTrack: RTCVideoTrack)
    func appClient(client: ARDAppClient, didError error: NSError)
}

// Handles connections to the AppRTC server for a given room
class ARDAppClient: NSObject {
    var state: ARDAppClientState?
    var delegate: ARDAppClientDelegate
    var serverHostURL: String
    
    var channel: ARDWebSocketChannel?
    var peerConnection: RTCPeerConnection?
    private var factory: RTCPeerConnectionFactory?
    var messageQueue: NSMutableArray
    
    var isTurnComplete: Bool?
    var hasReceivedSdp: Bool?
    var isRegisteredWithRoomServer: Bool {
        if let clientIDExists = clientID, clientIDExists.count > 0 {
            return true
        } else {
            return false
        }
    }
    var roomID: String?
    var clientID: String?
    var isInitiator: Bool?
    var isSpeakerEnabled: Bool
    var iceServers: NSMutableArray
    var webSocketURL: URL?
    var webSocketRestURL: URL?
    var defaultAudioTrack: RTCAudioTrack?
    var defaultVideoTrack: RTCVideoTrack?
    
    init(with delegate: ARDAppClientDelegate) {
        self.delegate = delegate
        messageQueue = NSMutableArray.init()
        iceServers = NSMutableArray.init(object: RTCICEServer.init(uri: URL(string: kARDDefaultSTUNServerUrl), username: "", password: ""))
        serverHostURL = kARDRoomServerHostUrl
        isSpeakerEnabled = true
        factory = RTCPeerConnectionFactory()
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: .UIDeviceOrientationDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .UIDeviceOrientationDidChange, object: nil)
        self.disconnect()
    }
    
    @objc func orientationChanged(notification: Notification) {
        print("ARDAppClient: orientationChanged(notification:)")
        let orientation = UIDevice.current.orientation
        if UIDeviceOrientationIsLandscape(orientation) || UIDeviceOrientationIsPortrait(orientation) {
            // remove current video track
            guard let localStream = peerConnection?.localStreams[0] as? RTCMediaStream else {
                print("ARDAppClient: orientationChanged(): could not get localStream as RTCMediaStream")
                return
            }
            localStream.removeVideoTrack(localStream.videoTracks.first as! RTCVideoTrack)
            
            if let localVideoTrack = self.createLocalVideoTrack() {
                localStream.addVideoTrack(localVideoTrack)
                delegate.appClient(client: self, didReceiveLocal: localVideoTrack)
            }
            peerConnection?.remove(localStream)
            peerConnection?.add(localStream)
        }
    }
    
    func setState(state: ARDAppClientState) {
        print("ARDAppClient: setState(state:)")
        if self.state == state {
            return
        }
        self.state = state
        delegate.appClient(client: self, didChange: self.state!)
    }
    
    // Establishes a connection with the AppRTC servers for the given room id.
    // TODO(tkchin): provide available keys/values for options. This will be used
    // for call configurations such as overriding server choice, specifying codecs
    // and so on.
    func connectToRoom(with roomID: String, options: NSDictionary?) {
        print("ARDAppClient: connectToRoom(with roomID)")
        // assert(roomID.characters.count > 0)
        // assert(self.state == ARDAppClientState.kARDAppClientStateDisconnected)
        setState(state: ARDAppClientState.kARDAppClientStateConnecting)
        
        // Request TURN
        guard let turnRequestURL = URL(string: kARDTurnRequestUrl) else {
            print("ARDAppClient: connectToRoom(with roomID): could not get turnRequestURL")
            return
        }
        requestTURNServersWithURL(requestURL: turnRequestURL) { [weak self] turnServers in
            for turnServer in turnServers {
                self?.iceServers.add(turnServer as Any)
            }
            // self?.iceServers.addObjects(from: turnServers)
            self?.isTurnComplete = true
            self?.startSignalingIfReady()
        }
        
        // Register with room server
        registerWithRoomServerForRoomID(roomID: roomID) { [weak self] response in
            if response == nil || response?.result == ARDRegisterResultType.kARDRegisterResultTypeFull {
                print("ARDAppClient: connectToRoom(with roomID:) Failed to register with room server.  Result: \(String(describing: response?.result))")
                self?.disconnect()
                
                let userInfo = [NSLocalizedDescriptionKey: "Room is full."]
                let error = NSError.init(domain: kARDAppClientErrorDomain, code: kARDAppClientErrorRoomFull, userInfo: userInfo)
                self?.delegate.appClient(client: self!, didError: error)
                return
            } else if response?.result == ARDRegisterResultType.kARDRegisterResultTypeUnknown {
                // Error in parsing response data
                self?.disconnect()
                let userInfo = [NSLocalizedDescriptionKey: "Unknown error occured"]
                let error = NSError.init(domain: kARDAppClientErrorDomain, code: kARDAppClientErrorUnknown, userInfo: userInfo)
                self?.delegate.appClient(client: self!, didError: error)
                return
            }
            print("ARDAppClient: connectToRoom(with roomID:) Registered with room server.")
            guard let responseIsInitiator = response?.isInitiator else {
                print("ARDAppClient: connectToRoom(with roomID:) response?.isInitiator is nil")
                return
            }
            self?.roomID = response?.roomID
            self?.clientID = response?.clientID
            self?.isInitiator = responseIsInitiator
            
            if let messages = response?.messages {
                for message in messages {
                    if let msg = message as? ARDSignalingMessage {
                        if msg.type == ARDSignalingMessageType.kARDSignalingMessageTypeOffer || msg.type == ARDSignalingMessageType.kARDSignalingMessageTypeAnswer {
                            self?.hasReceivedSdp = true
                            self?.messageQueue.insert(message, at: 0)
                        } else {
                            self?.messageQueue.add(message)
                        }
                    }
                }
            }
            
            guard let webSocketURL = response?.webSocketURL, let webSocketRestURL = response?.webSocketRestURL else {
                print("ARDAppClient: connectToRoom(with roomID:) response?.webSocketURL and/or response?.webSocketRestURL is/are nil")
                return
            }
            self?.webSocketURL = webSocketURL
            self?.webSocketRestURL = webSocketRestURL
            self?.registerWithColliderIfReady()
            self?.startSignalingIfReady()
        }
    }
    
    // MARK: - Audio mute/unmute
    func muteAudioIn() {
        print("ARDAppClient: muteAudioIn()")
        guard let localStream = peerConnection?.localStreams.first as? RTCMediaStream,
            let firstAudioTrack = localStream.audioTracks.first as? RTCAudioTrack else {
            print("ARDAppClient: muteAudioIn() could not get localStream as RTCMediaStream")
            return
        }
        
        defaultAudioTrack = firstAudioTrack
        localStream.removeAudioTrack(firstAudioTrack)
        peerConnection?.remove(localStream)
        peerConnection?.add(localStream)
    }
    
    func unmuteAudioIn() {
        print("ARDAppClient: unmuteAudioIn()")
        guard let localStream = peerConnection?.localStreams.first as? RTCMediaStream else {
            print("ARDAppClient: unmuteAudioIn() could not get localStream as RTCMediaStream")
            return
        }
        localStream.addAudioTrack(defaultAudioTrack)
        peerConnection?.remove(localStream)
        peerConnection?.add(localStream)
        if isSpeakerEnabled {
            enableSpeaker()
        }
    }
    
    // MARK: - Video mute/unmute
    func muteVideoIn() {
        print("ARDAppClient: muteVideoIn()")
        guard let localStream = peerConnection?.localStreams.first as? RTCMediaStream,
            let firstVideoTrack = localStream.videoTracks.first as? RTCVideoTrack else {
            print("ARDAppClient: muteVideoIn() could not get localStream as RTCMediaStream")
            return
        }
        defaultVideoTrack = firstVideoTrack
        localStream.removeVideoTrack(firstVideoTrack)
        peerConnection?.remove(localStream)
        peerConnection?.add(localStream)
    }
    
    func unmuteVideoIn() {
        print("ARDAppClient: unmuteVideoIn()")
        guard let localStream = peerConnection?.localStreams.first as? RTCMediaStream else {
            print("ARDAppClient: unmuteVideoIn() could not get localStream as RTCMediaStream")
            return
        }
        localStream.addVideoTrack(defaultVideoTrack)
        peerConnection?.remove(localStream)
        peerConnection?.add(localStream)
    }
    
    // MARK: - Swap camera functionality
    func createLocalVideoTrackBackCamera() -> RTCVideoTrack? {
        print("ARDAppClient: createLocalVideoTrackBackCamera()")
        var localVideoTrack: RTCVideoTrack? = nil

        // AVCaptureDevicePositionFront
        var cameraID: String? = nil
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        
        for captureDevice in deviceDiscoverySession.devices {
            if captureDevice.position == AVCaptureDevice.Position.back {
                cameraID = captureDevice.localizedName
                break
            }
        }
        
        assert(cameraID != nil, "ARDAppClient: createLocalVideoTrackBackCamera(): Unable to get the back camera id")
        
        let capturer = RTCVideoCapturer(deviceName: cameraID)
        let mediaConstraints = defaultMediaStreamConstraints()
        let videoSource = factory?.videoSource(with: capturer, constraints: mediaConstraints)
        localVideoTrack = factory?.videoTrack(withID: "ARDAMSv0", source: videoSource)

        return localVideoTrack
    }
    
    func swapCameraToFront() {
        print("ARDAppClient: swapCameraToFront()")
        guard let localStream = peerConnection?.localStreams.first as? RTCMediaStream,
            let firstVideoTrack = localStream.videoTracks.first as? RTCVideoTrack else {
            print("ARDAppClient: swapCameraToFront(): could not get localStream as RTCMediaStream")
            return
        }
        localStream.removeVideoTrack(firstVideoTrack)
        
        DispatchQueue.main.async {
            guard let localVideoTrack = self.createLocalVideoTrack() else {
                print("ARDAppClient: swapCameraToFront(): could not get localVideoTrack")
                return
            }
            localStream.addVideoTrack(localVideoTrack)
            self.delegate.appClient(client: self, didReceiveLocal: localVideoTrack)
            self.peerConnection?.remove(localStream)
            self.peerConnection?.add(localStream)
        }
    }
    
    func swapCameraToBack() {
        print("ARDAppClient: swapCameraToBack()")
        guard let localStream = peerConnection?.localStreams.first as? RTCMediaStream,
            let firstVideoTrack = localStream.videoTracks.first as? RTCVideoTrack else {
                print("ARDAppClient: swapCameraToBack(): could not get localStream as RTCMediaStream")
                return
        }
        localStream.removeVideoTrack(firstVideoTrack)
        
        DispatchQueue.main.async {
            guard let localVideoTrack = self.createLocalVideoTrackBackCamera() else {
                print("ARDAppClient: swapCameraToBack(): could not get localVideoTrack")
                return
            }
            localStream.addVideoTrack(localVideoTrack)
            self.delegate.appClient(client: self, didReceiveLocal: localVideoTrack)
            self.peerConnection?.remove(localStream)
            self.peerConnection?.add(localStream)
        }
    }
    
    // MARK: - Enabling / Disabling Speakerphone
    func enableSpeaker() {
        print("ARDAppClient: enableSpeaker()")
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
            try AVAudioSession.sharedInstance().setMode(AVAudioSessionModeVoiceChat)
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSessionPortOverride.speaker)
            try AVAudioSession.sharedInstance().setActive(true)
            isSpeakerEnabled = true
        } catch {
            print("ARDAppClient: enableSpeaker: Could not get speaker: \(error.localizedDescription)")
        }
    }
    
    func disableSpeaker() {
        print("ARDAppClient: disableSpeaker()")
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
            try AVAudioSession.sharedInstance().setMode(AVAudioSessionModeVoiceChat)
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(AVAudioSessionPortOverride.none)
            try AVAudioSession.sharedInstance().setActive(true)
            isSpeakerEnabled = false
        } catch {
            print("ARDAppClient: disableSpeaker: Could not get speaker: \(error.localizedDescription)")
        }
    }
    
    // Disconnects from the AppRTC servers and any connected ARDAppClientState
    func disconnect() {
        print("ARDAppClient: disconnect()")
        if state == ARDAppClientState.kARDAppClientStateDisconnected {
            return
        }
        if isRegisteredWithRoomServer {
            unregisterWithRoomServer()
        }
        if channel != nil {
            if channel?.state == ARDWebSocketChannelState.kARDWebSocketChannelStateRegistered {
                // Tell the other client we're hanging up.
                let byeMessage = ARDByeMessage.init()
                guard let byeData = byeMessage.JSONData() else {
                    print("ARDAppClient: disconnect() Could not get byeData")
                    return
                }
                channel?.sendData(data: byeData)
            }
            // Disconnect from collider
            channel = nil
        }
        clientID = nil
        roomID = nil
        isInitiator = false
        hasReceivedSdp = false
        messageQueue = NSMutableArray()
        peerConnection = nil
        setState(state: .kARDAppClientStateDisconnected)
    }
    
    // MARK: - Private
    func startSignalingIfReady() {
        print("ARDAppClient: startSignalingIfReady()")
        guard let isTurnComplete = self.isTurnComplete else {
            print("ARDAppClient: startSignalingIfReady() isTurnComplete is nil")
            return
        }
        if !isTurnComplete || !isRegisteredWithRoomServer {
            return
        }
        setState(state: .kARDAppClientStateConnected)
        
        // Create peer connection
        let constraints = defaultPeerConnectionConstraints()
        peerConnection = factory?.peerConnection(withICEServers: iceServers as! [Any], constraints: constraints, delegate: self)
        
        DispatchQueue.main.async {
            let localStream = self.createLocalMediaStream()
            self.peerConnection?.add(localStream)
            guard let isInitiator = self.isInitiator else {
                print("ARDAppClient: startSignalingIfReady(): isInitiator is nil")
                return
            }
            if isInitiator {
                self.sendOffer()
            } else {
                self.waitForAnswer()
            }
        }
    }
    
    func sendOffer() {
        print("ARDAppClient: sendOffer()")
        peerConnection?.createOffer(with: self, constraints: defaultOfferConstraints())
    }
    
    func waitForAnswer() {
        print("ARDAppClient: waitForAnswer()")
        drainMessageQueueIfReady()
    }
    
    func drainMessageQueueIfReady() {
        print("ARDAppClient: drainMessageQueueIfReady()")
        guard let hasReceivedSdp = self.hasReceivedSdp else {
            print("ARDAppClient: drainMessageQueueIfReady(): hasReceivedSdp is nil")
            return
        }
        if peerConnection == nil || !hasReceivedSdp {
            return
        }
        for message in messageQueue {
            guard let msg = message as? ARDSignalingMessage else {
                print("ARDAppClient: drainMessageQueueIfReady(), could not convert message to ARDSignalingMessage")
                return
            }
            processSignalingMessage(message: msg)
        }
        messageQueue.removeAllObjects()
    }
    
    func processSignalingMessage(message: ARDSignalingMessage) {
        print("ARDAppClient: processSignalingMessage(message) type: \(String(describing: message.type))")
        guard let type = message.type else {
            print("ARDAppClient: processSignalingMessage(message) Could not get message.type")
            return
        }
        assert(peerConnection != nil || type == ARDSignalingMessageType.kARDSignalingMessageTypeBye)
        switch type {
        case ARDSignalingMessageType.kARDSignalingMessageTypeOffer, ARDSignalingMessageType.kARDSignalingMessageTypeAnswer:
            guard let sdpMessage = message as? ARDSessionDescriptionMessage,
                let description = sdpMessage.sessionDescription else {
                print("ARDAppClient: processSignalingMessage(message): Could not convert message from ARDSignalingMessage to ARDSessionDescriptionMessage OR could not get message session description")
                return
            }
            peerConnection?.setRemoteDescriptionWith(self, sessionDescription: description)
        case ARDSignalingMessageType.kARDSignalingMessageTypeCandidate:
            guard let candidateMessage = message as? ARDICECandidateMessage else {
                print("ARDAppClient: processSignalingMessage(message): Could not convert message from ARDSignalingMessage to ARDICECandidateMessage")
                return
            }
            peerConnection?.add(candidateMessage.candidate)
        case ARDSignalingMessageType.kARDSignalingMessageTypeBye:
            // Other client disconnected.
            // TODO(tkchin): support waiting in room for next client. For now just
            // disconnect.
            disconnect()
        }
    }
    
    func sendSignalingMessage(message: ARDSignalingMessage) {
        print("ARDAppClient: startSignalingMessage(message:)")
        guard let isInitiator = self.isInitiator else {
            print("ARDAppClient: startSignalingMessage(message): isInitiator is nil")
            return
        }
        if isInitiator {
            sendSignalingMessageToRoomServer(message: message, completionHandler: {_ in})
        } else {
            sendSignalingMessageToCollider(message: message)
        }
    }
    
    func createLocalVideoTrack() -> RTCVideoTrack? {
        // The iOS simulator doesn't provide any sort of camera capture
        // support or emulation (http://goo.gl/rHAnC1) so don't bother
        // trying to open a local stream.
        // TODO(tkchin): local video capture for OSX. See
        // https://code.google.com/p/webrtc/issues/detail?id=3417.

        print("ARDAppClient: createLocalVideoTrack()")
        var localVideoTrack: RTCVideoTrack? = nil
        
        var cameraID: String? = nil
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        
        for captureDevice in deviceDiscoverySession.devices {
            if captureDevice.position == AVCaptureDevice.Position.front {
                cameraID = captureDevice.localizedName
                break
            }
        }
        assert(cameraID != nil, "ARDAppClient: createLocalVideoTrack() Unable to get the front camera id")

        guard let capturer = RTCVideoCapturer(deviceName: cameraID),
            let mediaConstraints = defaultMediaStreamConstraints() else {
                print("ARDAppClient: createLocalVideoTrack(): Could not get capturer and/or mediaConstraints")
                return nil
        }

        let videoSource = factory?.videoSource(with: capturer, constraints: mediaConstraints)
        localVideoTrack = factory?.videoTrack(withID: "ARDAMSv0", source: videoSource)
        
        return localVideoTrack
    }
    
    func createLocalMediaStream() -> RTCMediaStream? {
        print("ARDAppClient: createLocalMediaStream()")
        let localStream = factory?.mediaStream(withLabel: "ARDAMS")
        
        if let localVideoTrack = createLocalVideoTrack() {
            localStream?.addVideoTrack(localVideoTrack)
            delegate.appClient(client: self, didReceiveLocal: localVideoTrack)
        }
        
        localStream?.addAudioTrack(factory?.audioTrack(withID: "ARDAMSa0"))
        if isSpeakerEnabled {
            enableSpeaker()
        }
        return localStream
    }
    
    func requestTURNServersWithURL(requestURL: URL, completionHandler: @escaping ([RTCICEServer?]) -> ()) {
        print("ARDAppClient: requestTURNServersWithURL(requestURL:)")
        assert(requestURL.absoluteString.count > 0)
        var request = URLRequest.init(url: requestURL)
        // We need to set origin because TURN provider whitelists requests based on
        // origin.
        request.addValue("Mozilla/5.0", forHTTPHeaderField: "user-agent")
        request.addValue(serverHostURL, forHTTPHeaderField: "origin")
        URLSession.sendAsyncRequest(request: request) { (response, data, error) in
            if error != nil {
                print("ARDAppClient: requestTURNServer(): Unable to get TURN server")
                completionHandler([])
                return
            }
            guard let data = data else {
                print("ARDAppClient: requestTURNServersWithURL: Could not get dictionary from jsonData to be of type [String: Any]")
                return
            }
            let dict = NSDictionary.dictionaryWith(jsonData: data) as? [String: Any]
            let turnServers = RTCICEServer.serversFromCEOD(jsonDictionary: dict ?? [:])
            completionHandler(turnServers)
        }
    }
    
    // MARK: - Room server methods
    func registerWithRoomServerForRoomID(roomID: String, completionHandler: @escaping (ARDRegisterResponse?) -> ()) {
        print("ARDAppClient: registerWithRoomServerForRoomID()")
        let urlString = String(format: kARDRoomServerRegisterFormat, serverHostURL, roomID)
        guard let roomURL = URL(string: urlString) else {
            print("ARDAppClient: registerWithRoomServerForRoomID(): Could not get rooomURL with urlString")
            return
        }
        print("ARDAppClient: registerWithRoomServerForRoomID(): Registering with room server")
        URLSession.sendAsyncPostToURL(url: roomURL, data: nil) { [weak self] (succeeded, data) in
            if !succeeded {
                guard let error = self?.roomServerNetworkError() else {
                    print("ARDAppClient: registerWithRoomServerForRoomID(): Could not retrieve error")
                    return
                }
                self?.delegate.appClient(client: self!, didError: error)
                completionHandler(nil)
                return
            }
            guard let data = data else {
                print("ARDAppClient: registerWithRoomServerForRoomID(): data value is nil")
                return
            }
            let response = ARDRegisterResponse.responseFrom(jsonData: data)
            completionHandler(response)
        }
    }
    
    func sendSignalingMessageToRoomServer(message: ARDSignalingMessage, completionHandler: @escaping (ARDMessageResponse) -> ()) {
        print("ARDAppClient: sendSignalingMessageToRoomServer(message:)")
        let data = message.JSONData()
        guard let clientID = clientID, let roomID = roomID else {
            print("ARDAppClient: sendSignalingMessageToRoomServer(): Could not get clientID and/or roomID; value(s) is/are nil")
            return
        }
        let urlString = String(format: kARDRoomServerMessageFormat, serverHostURL, roomID, clientID)
        guard let url = URL(string: urlString) else {
            print("ARDAppClient: sendSignalingMessageToRoomServer(): Could not get url from urlString")
            return
        }
        
        print("ARDAppClient: sendSignalingMessageToRoomServer(): C->RS POST: \(String(describing: message.type))")
        URLSession.sendAsyncPostToURL(url: url, data: data) { [weak self] (succeeded, data) in
            if !succeeded {
                guard let error = self?.roomServerNetworkError() else {
                    print("ARDAppClient: sendSignalingMessageToRoomServer(): Could not retrieve error")
                    return
                }
                self?.delegate.appClient(client: self!, didError: error)
                return
            }
            guard let data = data,
                let response = ARDMessageResponse.responseFrom(jsonData: data),
                let result = response.result else {
                print("ARDAppClient: sendSignalingMessageToRoomServer(): data/response is nil")
                return
            }
            var error: NSError? = nil
            switch result {
            case ARDMessageResultType.kARDMessageResultTypeSuccess:
                break
            case ARDMessageResultType.kARDMessageResultTypeUnknown:
                error = NSError.init(domain: kARDAppClientErrorDomain,
                                             code: kARDAppClientErrorUnknown,
                                             userInfo: [NSLocalizedDescriptionKey: "Unknown Error"])
            case ARDMessageResultType.kARDMessageResultTypeInvalidClient:
                error = NSError.init(domain: kARDAppClientErrorDomain,
                                     code: kARDAppClientErrorInvalidClient,
                                     userInfo: [NSLocalizedDescriptionKey: "Invalid client"])
            case ARDMessageResultType.kARDMessageResultTypeInvalidRoom:
                error = NSError.init(domain: kARDAppClientErrorDomain,
                                     code: kARDAppClientErrorInvalidRoom,
                                     userInfo: [NSLocalizedDescriptionKey: "Invalid room"])
            }
            if let error = error {
                self?.delegate.appClient(client: self!, didError: error)
            }
            completionHandler(response)
        }
    }
    
    func unregisterWithRoomServer() {
        print("ARDAppClient: unregisterWithRoomServer()")
        guard let roomID = roomID, let clientID = clientID else {
            print("ARDAppClient: unregisterWithRoomServer(): roomID and/or clientID is nil")
            return
        }
        let urlString = String(format: kARDRoomServerByeFormat, serverHostURL, roomID, clientID)
        guard let url = URL(string: urlString) else {
            print("ARDAppClient: unregisterWithRoomServer(): Could not get url from urlString")
            return
        }
        print("ARDAppClient: unregisterWithRoomServer(): C->RS: BYE")
        // Make sure to do a POST
        URLSession.sendAsyncPostToURL(url: url, data: nil) { (succeeded, data) in
            if succeeded {
                print("ARDAppClient: unregisterWithRoomServer(): Unregistered from room server.")
            } else {
                print("ARDAppClient: unregisterWithRoomServer(): Failed to unregister from room server.")
            }
        }
    }
    
    func roomServerNetworkError() -> NSError {
        print("ARDAppClient: roomServerNetworkError()")
        let error = NSError(domain: kARDAppClientErrorDomain,
                            code: kARDAppClientErrorNetwork,
                            userInfo: [NSLocalizedDescriptionKey: "Room server network error"])
        return error
    }
    
    // MARK: - Collider methods
    func registerWithColliderIfReady() {
        print("ARDAppClient: registerWithColliderIfReady()")
        if !isRegisteredWithRoomServer {
            return
        }
        // Open WebSocket connection
        guard let webSocketURL = self.webSocketURL, let webSocketRestURL = self.webSocketRestURL else {
            print("ARDAppClient: registerWithColliderIfReady(): webSocketURL and/or webSocketRestURL is/are nil")
            return
        }
        channel = ARDWebSocketChannel(with: webSocketURL, restURL: webSocketRestURL, delegate: self)
        guard let roomID = roomID, let clientID = clientID else {
            print("ARDAppClient: registerWithColliderIfReady(): roomID and/or clientID is/are nil")
            return
        }
        channel?.registerFor(roomID: roomID, clientID: clientID)
    }
    
    func sendSignalingMessageToCollider(message: ARDSignalingMessage) {
        print("ARDAppClient: sendSignalingMessageToCollider(message)")
        guard let data = message.JSONData() else {
            print("ARDAppClient: sendSignalingMessageToCollider(message) Could not get data from message.JSONData()")
            return
        }
        channel?.sendData(data: data)
    }
    
    // MARK: - Defaults
    func defaultMediaStreamConstraints() -> RTCMediaConstraints? {
        print("ARDAppClient: defaultMediaStreamConstraints()")
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return constraints
    }
    
    func defaultAnswerConstraints() -> RTCMediaConstraints? {
        print("ARDAppClient: defaultAnswerConstraints()")
        return defaultOfferConstraints()
    }
    
    func defaultOfferConstraints() -> RTCMediaConstraints? {
        print("ARDAppClient: defaultOfferConstraints()")
        guard let audioRTCPair = RTCPair(key: "OfferToReceiveAudio", value: "true"),
            let videoRTCPair = RTCPair(key: "OfferToReceiveVideo", value: "true") else {
                print("ARDAppClient: defaultOfferConstraints(): Could not get RTCPair for audio nor video")
                return nil
        }
        let mandatoryConstraints = [audioRTCPair, videoRTCPair]
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints as [Any], optionalConstraints: nil)
        return constraints
    }
    
    func defaultPeerConnectionConstraints() -> RTCMediaConstraints? {
        print("ARDAppClient: defaultPeerConnectionConstraints()")
        guard let dtlsSrtpKeyAgreementRTCPair = RTCPair(key: "DtlsSrtpKeyAgreement", value: "true") else {
            print("ARDAppClient: defaultPeerConnectionConstraints(): Could not get RTCPair for dtlsSrtpKeyAgreement")
            return nil
        }
        let optionalConstraints = [dtlsSrtpKeyAgreementRTCPair]
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: optionalConstraints)
        return constraints
    }
    
    func defaultSTUNServer() -> RTCICEServer? {
        print("ARDAppClient: defaultSTUNServer()")
        guard let defaultSTUNServerURL = URL(string: kARDDefaultSTUNServerUrl) else {
            print("ARDAppClient: defaultSTUNServer(): Could not get stun server URL")
            return nil
        }
        return RTCICEServer(uri: defaultSTUNServerURL, username: "", password: "")
    }
}

extension ARDAppClient: ARDWebSocketChannelDelegate, RTCPeerConnectionDelegate, RTCSessionDescriptionDelegate {
    
    // MARK: - ARDWebSocketChannelDelegate
    func channel(channel: ARDWebSocketChannel, didReceive message: ARDSignalingMessage) {
        print("ARDAppClient: channel(didReceive message:)")
        guard let messageType = message.type else {
            print("ARDAppClient: channel(didReceive message) Could not unwrap message.type")
            return
        }
        switch messageType {
        case .kARDSignalingMessageTypeOffer, .kARDSignalingMessageTypeAnswer:
            hasReceivedSdp = true
            messageQueue.insert(message, at: 0)
            break
        case .kARDSignalingMessageTypeCandidate:
            messageQueue.add(message)
            break
        case .kARDSignalingMessageTypeBye:
            self.processSignalingMessage(message: message)
            return
        }
        self.drainMessageQueueIfReady()
    }
    
    func channel(channel: ARDWebSocketChannel, didChange state: ARDWebSocketChannelState) {
        print("ARDAppClient: channel(didChange state:)")
        switch state {
        case .kARDWebSocketChannelStateOpen:
            break
        case .kARDWebSocketChannelStateRegistered:
            break
        case .kARDWebSocketChannelStateClosed, .kARDWebSocketChannelStateError:
            // TODO(tkchin): reconnection scenarios. Right now we just disconnect
            // completely if the websocket connection fails.
            self.disconnect()
            break
        }
    }
    
    // MARK: - RTCPeerConnectionDelegate
    func peerConnection(_ peerConnection: RTCPeerConnection!, signalingStateChanged stateChanged: RTCSignalingState) {
        print("ARDAppClient: peerConnection(signalingStateChanged) Signaling state changed: \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, addedStream stream: RTCMediaStream!) {
        DispatchQueue.main.async {
            print("ARDAppClient: peerConnection(addedStream) Received \(stream.videoTracks.count) video tracks and \(stream.audioTracks.count) audio tracks")
            if stream.videoTracks.count > 0 {
                guard let videoTrack = stream.videoTracks.first as? RTCVideoTrack else {
                    print("ARDAppClient: peerConnection(addedStream) Could not get streamed videoTrack as RTCVideoTrack")
                    return
                }
                
                self.delegate.appClient(client: self, didReceiveRemote: videoTrack)
                if self.isSpeakerEnabled {
                    // Use the "handsfree" speaker instead of the ear speaker
                    self.enableSpeaker()
                }
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, removedStream stream: RTCMediaStream!) {
        print("ARDAppClient: peerConnection(removedStream) Stream was removed")
    }
    
    func peerConnection(onRenegotiationNeeded peerConnection: RTCPeerConnection!) {
        print("ARDAppClient: peerConnection(onRenegotiationNeeded) WARNING: Renegotiation needed but unimplemented.")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, iceConnectionChanged newState: RTCICEConnectionState) {
        print("ARDAppClient: peerConnection(iceConnectionChanged) ICE state changed: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, iceGatheringChanged newState: RTCICEGatheringState) {
        print("ARDAppClient: peerConnection(iceGatheringChanged) ICE gathering state changed: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, gotICECandidate candidate: RTCICECandidate!) {
        print("ARDAppClient: peerConnection(gotICECandidate:)")
        DispatchQueue.main.async {
            let message = ARDICECandidateMessage(with: candidate)
            self.sendSignalingMessage(message: message)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, didOpen dataChannel: RTCDataChannel!) {
        // No implementation
        print("ARDAppClient: peerConnection(didOpen dataChannel)")
    }
    
    // MARK: - RTCSessionDescriptionDelegate
    func peerConnection(_ peerConnection: RTCPeerConnection!, didCreateSessionDescription sdp: RTCSessionDescription!, error: Error!) {
        print("ARDAppClient: peerConnection(didCreateSessionDescription")
        DispatchQueue.main.async {
            if error != nil {
                print("ARDAppClient: peerConnection(didCreateSessionDescription) Failed to create session description.  Error: \(error)")
                self.disconnect()
                let userInfo = [NSLocalizedDescriptionKey: "Failed to create session description"]
                let sdpError = NSError.init(domain: kARDAppClientErrorDomain, code: kARDAppClientErrorCreateSDP, userInfo: userInfo)
                self.delegate.appClient(client: self, didError: sdpError)
                return
            }
            peerConnection.setLocalDescriptionWith(self, sessionDescription: sdp)
            let message = ARDSessionDescriptionMessage(with: sdp)
            self.sendSignalingMessage(message: message)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection!, didSetSessionDescriptionWithError error: Error!) {
        print("ARDAppClient: peerConnection(didSetSessionDescriptionWithError)")
        DispatchQueue.main.async {
            if error != nil {
                print("ARDAppClient: peerConnection(didSetSessionDescription) Failed to set session description.  Error: \(error)")
                self.disconnect()
                let userInfo = [NSLocalizedDescriptionKey: "Failed to set session description"]
                let sdpError = NSError.init(domain: kARDAppClientErrorDomain, code: kARDAppClientErrorSetSDP, userInfo: userInfo)
                self.delegate.appClient(client: self, didError: sdpError)
                return
            }
            // If we're answering and we've just set the remote offer we need to create
            // an answer and set the local description.
            guard let isInitiator = self.isInitiator else {
                print("ARDAppClient: peerConnect(didSetSessionDescriptionWithError)(): isInitiator is nil")
                return
            }
            if !isInitiator && peerConnection.localDescription == nil {
                let constraints = self.defaultAnswerConstraints()
                peerConnection.createAnswer(with: self, constraints: constraints)
            }
        }
    }
}
