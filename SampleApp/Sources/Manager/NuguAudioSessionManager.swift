//
//  NuguAudioSessionManager.swift
//  SampleApp
//
//  Created by jin kim on 2019/11/29.
//  Copyright (c) 2019 SK Telecom Co., Ltd. All rights reserved.
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
import UIKit

import NuguAgents

final class NuguAudioSessionManager {
    static let shared = NuguAudioSessionManager()
    private let defaultCategoryOptions = AVAudioSession.CategoryOptions(arrayLiteral: [.defaultToSpeaker, .allowBluetoothA2DP])
}

// MARK: - Internal

extension NuguAudioSessionManager {
    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission(response)
    }
    
    /// Update AudioSession.Category and AudioSession.CategoryOptions
    /// - Parameter requestingFocus: whether updating AudioSession is for requesting focus or just updating without requesting focus
    @discardableResult func updateAudioSession(requestingFocus: Bool = false) -> Bool {
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
            if UserDefaults.Standard.useWakeUpDetector == true {
                NuguCentralManager.shared.startMicInputProvider(requestingFocus: false) { success in
                    log.debug("startMicInputProvider : \(success)")
                }
            }
        }
        do {
            // Clean up all I/O before deactivating audioSession
            NuguCentralManager.shared.stopMicInputProvider()
            
            // Notify audio session deactivation to 3rd party apps
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.debug("notifyOthersOnDeactivation failed: \(error)")
        }
    }
}
