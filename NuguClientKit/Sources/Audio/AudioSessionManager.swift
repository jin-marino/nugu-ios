//
//  AudioSessionManager.swift
//  NuguClientKit
//
//  Created by 김진님/AI Assistant개발 Cell on 2021/01/07.
//  Copyright © 2021 SK Telecom Co., Ltd. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AVFoundation

import NuguAgents

final public class AudioSessionManager: AudioSessionManageable {
    private unowned var nuguClient: NuguClient
    
    private let defaultCategoryOptions = AVAudioSession.CategoryOptions(arrayLiteral: [.defaultToSpeaker, .allowBluetoothA2DP])
    private var audioSessionInterruptionObserver: Any?
    private var audioRouteObserver: Any?
    private var audioEngineConfigurationObserver: Any?
    private let notificationCenter = NotificationCenter.default
    private var audioPlayerStateObserver: Any?
    private var pausedByInterruption = false
    
    /// Initialize
    /// - Parameters:
    ///   - nuguClient: NuguClient instance which should be passed for delegation.
    public init(nuguClient: NuguClient) {
        self.nuguClient = nuguClient
        addAudioPlayerAgentObserver(nuguClient.audioPlayerAgent)
        // When no other audio is playing, audio session can not detect car play connectivity status even if car play has been already connected.
        // To resolve this problem, activating audio session should be done in prior to detecting car play connectivity.
        if AVAudioSession.sharedInstance().isOtherAudioPlaying == false {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        registerAudioSessionObservers()
    }
    
    deinit {
        if let audioPlayerStateObserver = audioPlayerStateObserver {
            notificationCenter.removeObserver(audioPlayerStateObserver)
        }
    }
}

// MARK: - Public

public extension AudioSessionManager {
    func isCarplayConnected() -> Bool {
        return AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType == AVAudioSession.Port.carAudio
    }
    
    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission(response)
    }
        
    @discardableResult func updateAudioSessionToPlaybackIfNeeded(mixWithOthers: Bool = false) -> Bool {
        var options = AVAudioSession.CategoryOptions(arrayLiteral: [])
        if mixWithOthers == true {
            options.insert(.mixWithOthers)
        }
        // If audioSession is already has been set properly, resetting audioSession is unnecessary
        guard isCarplayConnected() == true,
              AVAudioSession.sharedInstance().category != .playback ||
              AVAudioSession.sharedInstance().categoryOptions != options else { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: options
            )
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch {
            log.debug("updateAudioSessionToPlaybackIfNeeded failed: \(error)")
            return false
        }
    }
    
    @discardableResult func updateAudioSessionWhenCarplayConnected(requestingFocus: Bool) -> Bool {
        if requestingFocus == true {
            let options = AVAudioSession.CategoryOptions(arrayLiteral: [])
            // If audioSession is already has been set properly, resetting audioSession is unnecessary
            guard AVAudioSession.sharedInstance().category != .playAndRecord ||
                  AVAudioSession.sharedInstance().categoryOptions != options else {
                return true
            }
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: []
                )
                try AVAudioSession.sharedInstance().setActive(true)
                return true
            } catch {
                log.debug("updateAudioSession when carplay connected has failed: \(error)")
                return false
            }
        } else {
            return updateAudioSessionToPlaybackIfNeeded(mixWithOthers: true)
        }
    }
    
    /// Update AudioSession.Category and AudioSession.CategoryOptions
    /// - Parameter requestingFocus: whether updating AudioSession is for requesting focus or just updating without requesting focus
    @discardableResult func updateAudioSession(requestingFocus: Bool = false) -> Bool {
        guard isCarplayConnected() == false else {
            return updateAudioSessionWhenCarplayConnected(requestingFocus: requestingFocus)
        }
        
        var options = defaultCategoryOptions
        if requestingFocus == false {
            options.insert(.mixWithOthers)
        }
        
        // If audioSession is already has been set properly, resetting audioSession is unnecessary
        guard AVAudioSession.sharedInstance().category != .playAndRecord || AVAudioSession.sharedInstance().categoryOptions != options else {
            return true
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: options
            )
            try AVAudioSession.sharedInstance().setActive(true)
            log.debug("set audio session = \(options)")
            return true
        } catch {
            log.debug("updateAudioSessionCategoryOptions failed: \(error)")
            return false
        }
    }
    
    func notifyAudioSessionDeactivation() {
        log.debug("")
        // Defer statement for recovering audioSession and MicInputProvider
        defer {
            updateAudioSession()
            nuguClient.speechRecognizerAggregator?.startListeningWithTrigger()
        }
        do {
            // Clean up all I/O before deactivating audioSession
            nuguClient.speechRecognizerAggregator?.stopListening()
            
            // Notify audio session deactivation to 3rd party apps
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.debug("notifyOthersOnDeactivation failed: \(error)")
        }
    }
}

// MARK: - Public (AudioEngineObserver)

public extension AudioSessionManager {
    func registerAudioEngineConfigurationObserver() {
        removeAudioEngineConfigurationObserver()
        
        audioEngineConfigurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil, using: { [weak self] (_) in
            self?.nuguClient.speechRecognizerAggregator?.startListeningWithTrigger()
        })
    }
    
    func removeAudioEngineConfigurationObserver() {
        if let audioEngineConfigurationObserver = audioEngineConfigurationObserver {
            NotificationCenter.default.removeObserver(audioEngineConfigurationObserver)
            self.audioEngineConfigurationObserver = nil
        }
    }
}

// MARK: - private (AudioSessionObserver)

private extension AudioSessionManager {
    func registerAudioSessionObservers() {
        removeAudioSessionObservers()
        
        audioSessionInterruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil, using: { [weak self] (notification) in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
            switch type {
            case .began:
                log.debug("Interruption began")
                // Interruption began, take appropriate actions
                if self?.nuguClient.audioPlayerAgent.isPlaying == true {
                    self?.nuguClient.audioPlayerAgent.pause()
                    // PausedByInterruption flag should not be changed before paused delegate method has been called
                    // Giving small delay for changing flag value can be a solution for this situation
                    DispatchQueue.global().asyncAfter(deadline: .now()+0.1) { [weak self] in
                        self?.pausedByInterruption = true
                    }
                }
                self?.nuguClient.ttsAgent.stopTTS(cancelAssociation: false)
                self?.nuguClient.speechRecognizerAggregator?.stopListening()
            case .ended:
                log.debug("Interruption ended")
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        if self?.nuguClient.speechRecognizerAggregator?.useKeywordDetector == true {
                            self?.nuguClient.speechRecognizerAggregator?.startListeningWithTrigger()
                        }
                        if self?.pausedByInterruption == true || self?.nuguClient.audioPlayerAgent.isPlaying == true {
                            self?.nuguClient.audioPlayerAgent.play()
                        }
                    } else {
                        // Interruption Ended - playback should NOT resume
                    }
                }
            @unknown default: break
            }
        })
        
        audioRouteObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil, using: { [weak self] (notification) in
            guard let userInfo = notification.userInfo,
                let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
            switch reason {
            case .oldDeviceUnavailable:
                log.debug("Route changed due to oldDeviceUnavailable")
                if self?.nuguClient.audioPlayerAgent.isPlaying == true {
                    self?.nuguClient.audioPlayerAgent.pause()
                }
                if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
                   previousRoute.outputs.first?.portType == .carAudio {
                    self?.updateAudioSession()
                    self?.nuguClient.speechRecognizerAggregator?.startListeningWithTrigger()
                }
            case .newDeviceAvailable:
                if self?.isCarplayConnected() == true {
                    self?.nuguClient.speechRecognizerAggregator?.stopListening()
                    self?.updateAudioSession()
                }
                if self?.nuguClient.audioPlayerAgent.isPlaying == true {
                    self?.updateAudioSessionToPlaybackIfNeeded()
                }
            default: break
            }
        })
    }
    
    func removeAudioSessionObservers() {
        if let audioSessionInterruptionObserver = audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(audioSessionInterruptionObserver)
            self.audioSessionInterruptionObserver = nil
        }
        
        if let audioRouteObserver = audioRouteObserver {
            NotificationCenter.default.removeObserver(audioRouteObserver)
            self.audioRouteObserver = nil
        }
    }
}

// MARK: - Private (audioPlayerStateObserver)

private extension AudioSessionManager {
    func addAudioPlayerAgentObserver(_ object: AudioPlayerAgentProtocol) {
        audioPlayerStateObserver = object.observe(NuguAgentNotification.AudioPlayer.State.self, queue: .main) { [weak self] (notification) in
            guard let self = self else { return }
            
            if notification.state == .playing && self.isCarplayConnected() == true {
                self.updateAudioSessionToPlaybackIfNeeded()
            }
        }
    }
}