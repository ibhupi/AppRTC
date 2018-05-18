//
//  ARTCVideoChatViewController.swift
//  AppRTCSwift
//
//  Created by Brandon Tyler on 8/14/17.
//  Copyright © 2017 Brandon Maynard. All rights reserved.
//

import UIKit
import AVFoundation

let SERVER_HOST_URL = "https://appr.tc"

class ARTCVideoChatViewController: UIViewController {

    // Views, Labels, and Buttons
    @IBOutlet weak var remoteView: RTCEAGLVideoView!
    @IBOutlet weak var localView: RTCEAGLVideoView!
    @IBOutlet weak var footerView: UIView!
    @IBOutlet weak var urlLabel: UILabel!
    @IBOutlet weak var buttonContainerView: UIView!
    @IBOutlet weak var audioButton: UIButton!
    @IBOutlet weak var videoButton: UIButton!
    @IBOutlet weak var hangupButton: UIButton!
    
    // Auto Layout Constraints used for animations
    @IBOutlet weak var remoteViewTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var remoteViewRightConstraint: NSLayoutConstraint!
    @IBOutlet weak var remoteViewLeftConstraint: NSLayoutConstraint!
    @IBOutlet weak var remoteViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var localViewWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var localViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var localViewRightConstraint: NSLayoutConstraint!
    @IBOutlet weak var localViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var footerViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var buttonContainerViewLeftConstraint: NSLayoutConstraint!
    
    var roomUrl: String!
    var roomName: String!
    var client: ARDAppClient?
    var localVideoTrack: RTCVideoTrack?
    var remoteVideoTrack: RTCVideoTrack?
    var localVideoSize: CGSize?
    var remoteVideoSize: CGSize?
    var isZoom: Bool? // used for double tap remote view
    
    // toggle button parameter
    var isAudioMute: Bool?
    var isVideoMute: Bool?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.isZoom = false
        self.isAudioMute = false
        self.isVideoMute = false
        
        self.audioButton.layer.cornerRadius = 20.0
        self.videoButton.layer.cornerRadius = 20.0
        self.hangupButton.layer.cornerRadius = 20.0
        
        // Add Tap to hide/show controls
        var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(toggleButtonContainer))
        tapGestureRecognizer.numberOfTapsRequired = 1
        self.view.addGestureRecognizer(tapGestureRecognizer)
        
        // Add Double Tap to zoom
        tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(zoomRemote))
        tapGestureRecognizer.numberOfTapsRequired = 2
        self.view.addGestureRecognizer(tapGestureRecognizer)
        
        // RTCEAGLVideoViewDelegate provides notifications on video frame dimensions
        self.remoteView.delegate = self
        self.localView.delegate = self
        
        // Getting Orientation change
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationChanged),
                                               name: NSNotification.Name.UIDeviceOrientationDidChange,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(resigningActive), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.navigationController?.setNavigationBarHidden(true, animated: true)
        
        // Display the Local View full screen while connecting to Room
        self.localViewBottomConstraint.constant = 0.0
        self.localViewRightConstraint.constant = 0.0
        self.localViewHeightConstraint.constant = self.view.frame.size.height
        self.localViewWidthConstraint.constant = self.view.frame.size.width
        self.footerViewBottomConstraint.constant = 0.0
        
        // Connect to the room
        self.disconnect()
        self.client = ARDAppClient(with: self)
        self.client?.serverHostURL = SERVER_HOST_URL
        self.client?.connectToRoom(with: self.roomName, options: nil)
        
        self.urlLabel.text = self.roomUrl
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self,
                                                  name: NSNotification.Name.UIDeviceOrientationDidChange,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        self.disconnect()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @objc func resigningActive() {
        self.disconnect()
    }
    
    @objc func orientationChanged() {
        guard let localVideoSize = self.localVideoSize, let remoteVideoSize = self.remoteVideoSize else {
            print("ARTCVideoChatViewController: orientationChanged(): localVideoSize and/or remoteVideoSize is/are nil")
            return
        }
        self.videoView(self.localView, didChangeVideoSize: localVideoSize)
        self.videoView(self.remoteView, didChangeVideoSize: remoteVideoSize)
    }
    
    private func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    func setRoomName(name: String) {
        self.roomName = name
        self.roomUrl = "\(SERVER_HOST_URL)/r/\(roomName)"
    }
    
    func disconnect() {
        guard let _ = client else {
            print("ARTCVideoChatController: disconnect(): client is nil")
            return
        }
        if self.localVideoTrack != nil {
            self.localVideoTrack?.remove(self.localView)
        }
        if self.remoteVideoTrack != nil {
            self.remoteVideoTrack?.remove(self.remoteView)
        }
        self.localVideoTrack = nil
        self.localView.renderFrame(nil)
        self.remoteVideoTrack = nil
        self.remoteView.renderFrame(nil)
        self.client?.disconnect()
    }
    
    func remoteDisconnected() {
        if self.remoteVideoTrack != nil {
            self.remoteVideoTrack?.remove(self.remoteView)
        }
        self.remoteVideoTrack = nil
        self.remoteView.renderFrame(nil)
        guard let localVideoSize = self.localVideoSize else {
            print("ARTCVideoChatViewController: remoteDisconnected(): localVideoSize is nil")
            return
        }
        self.videoView(self.localView, didChangeVideoSize: localVideoSize)
    }
    
    @objc func toggleButtonContainer() {
        UIView.animate(withDuration: 0.3) { [weak self] in
            if let buttonContainerLeftConstant = self?.buttonContainerViewLeftConstraint.constant, buttonContainerLeftConstant <= CGFloat(-40.0) {
                self?.buttonContainerViewLeftConstraint.constant = 20.0
                self?.buttonContainerView.alpha = 1.0
            } else {
                self?.buttonContainerViewLeftConstraint.constant = -40.0
                self?.buttonContainerView.alpha = 0.0
            }
            self?.view.layoutIfNeeded()
        }
    }
    
    @objc func zoomRemote() {
        // Toggle Aspect Fill or Fit
        guard let isZoom = self.isZoom, let remoteVideoSize = self.remoteVideoSize else {
            print("ARTCVideoChatViewController: zoomRemote(): isZoom is nil and/or remoteVideoSize is nil")
            return
        }
        self.isZoom = !isZoom
        self.videoView(self.remoteView, didChangeVideoSize: remoteVideoSize)
    }
    
    @IBAction func audioButtonPressed(_ sender: UIButton) {
        // TODO: this change not work on simulator (it will crash)
        let audioButton = sender
        if let audioMute = self.isAudioMute, audioMute == true {
            self.client?.unmuteAudioIn()
            audioButton.setImage(UIImage(named: "audioOn"), for: .normal)
            self.isAudioMute = false
        } else {
            self.client?.muteAudioIn()
            audioButton.setImage(UIImage(named: "audioOff"), for: .normal)
            self.isAudioMute = true
        }
    }
    
    @IBAction func videoButtonPressed(_ sender: UIButton) {
        let videoButton = sender
        if let isFrontVideo = self.isVideoMute, isFrontVideo == true {
            // self.client.unmuteVideoIn()
            self.client?.swapCameraToFront()
            videoButton.setImage(UIImage(named: "videoOn"), for: .normal)
            self.isVideoMute = false
        } else {
            self.client?.swapCameraToBack()
            // self.client.muteVideoIn()
            // videoButton.setImaget(UIImage(named: "videoOff"), for: .normal)
            self.isVideoMute = true
        }
    }
    
    @IBAction func hangupButtonPressed(_ sender: UIButton) {
        // Clean up
        self.disconnect()
        self.navigationController?.popToRootViewController(animated: true)
    }
}

extension ARTCVideoChatViewController: ARDAppClientDelegate, RTCEAGLVideoViewDelegate {
    
    // MARK: - ARDAppClientDelegate
    func appClient(client: ARDAppClient, didChange state: ARDAppClientState) {
        switch state {
        case ARDAppClientState.kARDAppClientStateConnected:
            print("ARTCVideoChatController: appClient(didChange state): Client connected")
        case ARDAppClientState.kARDAppClientStateConnecting:
            print("ARTCVideoChatController: appClient(didChange state): Client connecting")
        case ARDAppClientState.kARDAppClientStateDisconnected:
            print("ARTCVideoChatController: appClient(didChange state): Client disconnected")
            remoteDisconnected()
        }
    }
    
    func appClient(client: ARDAppClient, didReceiveLocal videoTrack: RTCVideoTrack) {
        if self.localVideoTrack != nil {
            self.localVideoTrack?.remove(localView)
            self.localVideoTrack = nil
            localView.renderFrame(nil)
        }
        self.localVideoTrack = videoTrack
        self.localVideoTrack?.add(localView)
    }
    
    
    
    func appClient(client: ARDAppClient, didReceiveRemote videoTrack: RTCVideoTrack) {
        self.remoteVideoTrack = videoTrack
        self.remoteVideoTrack?.add(remoteView)
        
        UIView.animate(withDuration: 0.4) { 
            // Instead of using 0.4 of screen size, we re-calculate the local view and keep our aspect ratio
            let orientation = UIDevice.current.orientation
            var videoRect = CGRect(x: 0.0, y: 0.0, width: self.view.frame.size.width/4.0, height: self.view.frame.size.height/4.0)
            if orientation == UIDeviceOrientation.landscapeLeft || orientation == UIDeviceOrientation.landscapeRight {
                videoRect = CGRect(x: 0.0, y: 0.0, width: self.view.frame.size.height/4.0, height: self.view.frame.size.width/4.0)
            }
            let videoFrame = AVMakeRect(aspectRatio: self.localView.frame.size, insideRect: videoRect)
            
            self.localViewWidthConstraint.constant = videoFrame.size.width
            self.localViewHeightConstraint.constant = videoFrame.size.height
            
            self.localViewBottomConstraint.constant = 28.0
            self.localViewRightConstraint.constant = 28.0
            self.footerViewBottomConstraint.constant = -80.0
            self.view.layoutIfNeeded()
        }
    }
    
    func appClient(client: ARDAppClient, didError error: NSError) {
        let alertView = UIAlertController(title: nil, message: String(describing: error), preferredStyle: .alert)
        alertView.show(self, sender: nil)
        disconnect()
    }
    
    // MARK: - RTCEAGLVideoViewDelegate
    func videoView(_ videoView: RTCEAGLVideoView!, didChangeVideoSize size: CGSize) {
        let orientation = UIDevice.current.orientation
        UIView.animate(withDuration: 0.4) { 
            let containerWidth = self.view.frame.size.width
            let containerHeight = self.view.frame.size.height
            let defaultAspectRatio = CGSize(width: 4, height: 3)
            if videoView == self.localView {
                // Resize the Local View depending if it is full screen or thumbnail
                self.localVideoSize = size
                let aspectRatio = __CGSizeEqualToSize(size, CGSize.zero) ? defaultAspectRatio : size
                var videoRect = self.view.bounds
                if self.remoteVideoTrack != nil {
                    videoRect = CGRect(x: 0.0, y: 0.0, width: self.view.frame.size.width/4.0, height: self.view.frame.size.height/4.0)
                    if orientation == UIDeviceOrientation.landscapeLeft || orientation == UIDeviceOrientation.landscapeRight {
                        videoRect = CGRect(x: 0.0, y: 0.0, width: self.view.frame.size.height/4.0, height: self.view.frame.size.width/4.0)
                    }
                }
                let videoFrame = AVMakeRect(aspectRatio: aspectRatio, insideRect: videoRect)
                
                // Resize the localView accordingly
                self.localViewWidthConstraint.constant = videoFrame.size.width
                self.localViewHeightConstraint.constant = videoFrame.size.height
                if self.remoteVideoTrack != nil {
                    self.localViewBottomConstraint.constant = 28.0 // bottom right corner
                    self.localViewRightConstraint.constant = 28.0
                } else {
                    self.localViewBottomConstraint.constant = containerHeight/2.0 - videoFrame.size.height/2.0 // center
                    self.localViewRightConstraint.constant = containerWidth/2.0 - videoFrame.size.width/2.0 // center
                }
            } else if videoView == self.remoteView {
                // Resize Remote View
                self.remoteVideoSize = size
                let aspectRatio = __CGSizeEqualToSize(size, CGSize.zero) ? defaultAspectRatio : size
                let videoRect = self.view.bounds
                var videoFrame = AVMakeRect(aspectRatio: aspectRatio, insideRect: videoRect)
                if self.isZoom == true {
                    // Set Aspect Fill
                    let scale = max(containerWidth/videoFrame.size.width, containerHeight/videoFrame.size.height)
                    videoFrame.size.width *= scale
                    videoFrame.size.height *= scale
                }
                self.remoteViewTopConstraint.constant = containerHeight/2.0 - videoFrame.size.height/2.0
                self.remoteViewBottomConstraint.constant = containerHeight/2.0 - videoFrame.size.height/2.0
                self.remoteViewLeftConstraint.constant = containerWidth/2.0 - videoFrame.size.width/2.0 // center
                self.remoteViewRightConstraint.constant = containerWidth/2.0 - videoFrame.size.width/2.0 // center
            }
            self.view.layoutIfNeeded()
        }
    }
}
