//
//  MainViewController.swift
//  SampleApp
//
//  Created by jin kim on 17/06/2019.
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

import UIKit

import NuguCore
import NuguAgents
import NuguClientKit
import NuguUIKit

final class MainViewController: UIViewController {
    
    // MARK: Properties
    
    @IBOutlet private weak var nuguButton: NuguButton!
    @IBOutlet private weak var settingButton: UIButton!
    
    private var voiceChromeDismissWorkItem: DispatchWorkItem?
    private var nuguVoiceChrome = NuguVoiceChrome()
    
    // MARK: Override
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        initializeNugu()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willResignActive(_:)),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        refreshNugu()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NuguCentralManager.shared.stopMicInputProvider()
    }
    
    // MARK: Deinitialize
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Private (Selector)

@objc private extension MainViewController {
    
    /// Catch resigning active notification to stop recognizing & wake up detector
    /// It is possible to keep on listening even on background, but need careful attention for battery issues, audio interruptions and so on
    /// - Parameter notification: UIApplication.willResignActiveNotification
    func willResignActive(_ notification: Notification) {
        dismissVoiceChrome()
        // if tts is playing for multiturn, tts and associated jobs should be stopped when resign active
        if NuguCentralManager.shared.client.dialogStateAggregator.isMultiturn == true {
            NuguCentralManager.shared.client.ttsAgent.stopTTS()
        }
        NuguCentralManager.shared.client.asrAgent.stopRecognition()
        NuguCentralManager.shared.stopMicInputProvider()
    }
    
    /// Catch becoming active notification to refresh mic status & Nugu button
    /// Recover all status for any issues caused from becoming background
    /// - Parameter notification: UIApplication.didBecomeActiveNotification
    func didBecomeActive(_ notification: Notification) {
        guard navigationController?.visibleViewController == self else { return }
        refreshNugu()
    }
        
    func didTapForDismissVoiceChrome() {
        guard nuguVoiceChrome.currentState == .listeningPassive || nuguVoiceChrome.currentState == .listeningActive  else { return }
        dismissVoiceChrome()
        NuguCentralManager.shared.client.asrAgent.stopRecognition()
    }
}

// MARK: - Private (IBAction)

private extension MainViewController {
    @IBAction func showSettingsButtonDidClick(_ button: UIButton) {
        NuguCentralManager.shared.stopMicInputProvider()

        performSegue(withIdentifier: "showSettings", sender: nil)
    }
    
    @IBAction func startRecognizeButtonDidClick(_ button: UIButton) {
        presentVoiceChrome(initiator: .user)
    }
}

// MARK: - Private (Nugu)

private extension MainViewController {
    
    /// Initialize to start using Nugu
    /// AudioSession is required for using Nugu
    /// Add delegates for all the components that provided by default client or custom provided ones
    func initializeNugu() {
        // Set AudioSession
        NuguAudioSessionManager.shared.updateAudioSession()
        
        // Add delegates
        NuguCentralManager.shared.client.keywordDetector.delegate = self
        NuguCentralManager.shared.client.dialogStateAggregator.add(delegate: self)
        NuguCentralManager.shared.client.asrAgent.add(delegate: self)
        NuguCentralManager.shared.client.mediaPlayerAgent.delegate = self
    }
    
    /// Refresh Nugu status
    /// Connect or disconnect Nugu service by circumstance
    /// Hide Nugu button when Nugu service is intended not to use or network issue has occured
    /// Disable Nugu button when wake up feature is intended not to use
    func refreshNugu() {
        guard UserDefaults.Standard.useNuguService else {
            // Exception handling when already disconnected, scheduled update in future
            nuguButton.isEnabled = false
            nuguButton.isHidden = true
            
            // Disable Nugu SDK
            NuguCentralManager.shared.disable()
            return
        }
        
        // Exception handling when already connected, scheduled update in future
        nuguButton.isEnabled = true
        nuguButton.isHidden = false
        
        // Enable Nugu SDK
        NuguCentralManager.shared.enable()
    }
}

// MARK: - Private (Voice Chrome)

private extension MainViewController {
    func presentVoiceChrome(initiator: ASRInitiator) {
        voiceChromeDismissWorkItem?.cancel()
        nuguVoiceChrome.removeFromSuperview()
        nuguVoiceChrome = NuguVoiceChrome(frame: CGRect(x: 0, y: self.view.frame.size.height, width: self.view.frame.size.width, height: NuguVoiceChrome.recommendedHeight + SampleApp.bottomSafeAreaHeight))
        view.addSubview(self.nuguVoiceChrome)
        showVoiceChrome()
        nuguButton.isActivated = false
        
        NuguCentralManager.shared.startMicInputProvider(requestingFocus: true) { [weak self] success in
            guard let self = self else { return }
            guard success else {
                log.error("Start MicInputProvider failed")
                DispatchQueue.main.async { [weak self] in
                    self?.dismissVoiceChrome()
                }
                return
            }
            
            NuguCentralManager.shared.startRecognition(initiator: initiator)
        }
    }
    
    func showVoiceChrome() {
        let showAnimation = {
            UIView.animate(withDuration: 0.3) { [weak self] in
                guard let self = self else { return }
                self.nuguVoiceChrome.transform = CGAffineTransform(translationX: 0.0, y: -self.nuguVoiceChrome.bounds.height)
            }
        }
        
        if view.subviews.contains(nuguVoiceChrome) == false {
            nuguVoiceChrome = NuguVoiceChrome(frame: CGRect(x: 0, y: view.frame.size.height, width: view.frame.size.width, height: NuguVoiceChrome.recommendedHeight + SampleApp.bottomSafeAreaHeight))
            view.addSubview(nuguVoiceChrome)
            showAnimation()
        } else {
            if nuguVoiceChrome.frame.origin.y != view.frame.size.height - nuguVoiceChrome.bounds.height {
                showAnimation()
            }
        }
        addTapGestureRecognizerForDismissVoiceChrome()
    }
    
    func dismissVoiceChrome() {
        view.gestureRecognizers = nil
        
        voiceChromeDismissWorkItem?.cancel()
        
        nuguButton.isActivated = true
        
        UIView.animate(withDuration: 0.3, animations: { [weak self] in
            guard let self = self else { return }
            self.nuguVoiceChrome.transform = CGAffineTransform(translationX: 0.0, y: self.nuguVoiceChrome.bounds.height)
        }, completion: { [weak self] _ in
            self?.nuguVoiceChrome.removeFromSuperview()
        })
    }
    
    func addTapGestureRecognizerForDismissVoiceChrome() {
        view.gestureRecognizers?.forEach { view.removeGestureRecognizer($0) }
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapForDismissVoiceChrome))
        view.addGestureRecognizer(tapGestureRecognizer)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MainViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let touchLocation = touch.location(in: gestureRecognizer.view)
        return !nuguVoiceChrome.frame.contains(touchLocation)
    }
}

// MARK: - KeywordDetectorDelegate

extension MainViewController: KeywordDetectorDelegate {
    func keywordDetectorDidDetect(keyword: String?, data: Data, start: Int, end: Int, detection: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.presentVoiceChrome(initiator: .wakeUpKeyword(
                keyword: keyword,
                data: data,
                start: start,
                end: end,
                detection: detection
                )
            )
        }
    }
    
    func keywordDetectorDidStop() {}
    
    func keywordDetectorStateDidChange(_ state: KeywordDetectorState) {
        switch state {
        case .active:
            DispatchQueue.main.async { [weak self] in
                self?.nuguButton.startFlipAnimation()
            }
        case .inactive:
            DispatchQueue.main.async { [weak self] in
                self?.nuguButton.stopFlipAnimation()
            }
        }
    }
    
    func keywordDetectorDidError(_ error: Error) {}
}

// MARK: - DialogStateDelegate

extension MainViewController: DialogStateDelegate {
    func dialogStateDidChange(_ state: DialogState, isMultiturn: Bool, chips: [ChipsAgentItem.Chip]?, sessionActivated: Bool) {
        log.debug("\(state) \(isMultiturn), \(chips.debugDescription)")
        switch state {
        case .idle:
            if case SamplePlayer.State.paused(temporary: true) = NuguCentralManager.shared.samplePlayer.state {
                NuguCentralManager.shared.samplePlayer.resume()
            }
            voiceChromeDismissWorkItem = DispatchWorkItem(block: { [weak self] in
                self?.dismissVoiceChrome()
            })
            guard let voiceChromeDismissWorkItem = voiceChromeDismissWorkItem else { break }
            DispatchQueue.main.async(execute: voiceChromeDismissWorkItem)
        case .speaking:
            voiceChromeDismissWorkItem?.cancel()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard isMultiturn == true else {
                    self.dismissVoiceChrome()
                    return
                }
                // If voice chrome is not showing or dismissing in speaking state, voice chrome should be presented
                self.showVoiceChrome()
                self.nuguVoiceChrome.changeState(state: .speaking)
            }
        case .listening:
            if case SamplePlayer.State.playing = NuguCentralManager.shared.samplePlayer.state {
                NuguCentralManager.shared.samplePlayer.pause(temporary: true)
            }
            voiceChromeDismissWorkItem?.cancel()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // If voice chrome is not showing or dismissing in listening state, voice chrome should be presented
                self.showVoiceChrome()
                if isMultiturn || sessionActivated {
                    self.nuguVoiceChrome.changeState(state: .listeningPassive)
                    self.nuguVoiceChrome.setRecognizedText(text: nil)
                    self.nuguButton.isActivated = false
                }
                NuguCentralManager.shared.asrBeepPlayer.beep(type: .start)
            }
        case .recognizing:
            DispatchQueue.main.async { [weak self] in
                self?.nuguVoiceChrome.changeState(state: .listeningActive)
            }
        case .thinking:
            DispatchQueue.main.async { [weak self] in
                self?.nuguVoiceChrome.changeState(state: .processing)
                self?.nuguButton.pauseDeactivateAnimation()
            }
        }
    }
}

// MARK: - AutomaticSpeechRecognitionDelegate

extension MainViewController: ASRAgentDelegate {
    func asrAgentDidChange(state: ASRState) {
        switch state {
        case .idle:
            if UserDefaults.Standard.useWakeUpDetector == true {
                NuguCentralManager.shared.startWakeUpDetector()
            } else {
                NuguCentralManager.shared.stopMicInputProvider()
            }
        case .listening:
            NuguCentralManager.shared.stopWakeUpDetector()
        case .expectingSpeech:
            NuguCentralManager.shared.startMicInputProvider(requestingFocus: true) { (success) in
                guard success == true else {
                    log.debug("startMicInputProvider failed!")
                    NuguCentralManager.shared.stopRecognition()
                    return
                }
            }
        default:
            break
        }
    }
    
    func asrAgentDidReceive(result: ASRResult, dialogRequestId: String) {
        switch result {
        case .complete(let text):
            DispatchQueue.main.async { [weak self] in
                self?.nuguVoiceChrome.setRecognizedText(text: text)
                NuguCentralManager.shared.asrBeepPlayer.beep(type: .success)
            }
        case .partial(let text):
            DispatchQueue.main.async { [weak self] in
                self?.nuguVoiceChrome.setRecognizedText(text: text)
            }
        case .error(let error):
            DispatchQueue.main.async { [weak self] in
                switch error {
                case ASRError.listenFailed:
                    NuguCentralManager.shared.asrBeepPlayer.beep(type: .fail)
                    self?.nuguVoiceChrome.changeState(state: .speakingError)
                case ASRError.recognizeFailed:
                    NuguCentralManager.shared.localTTSAgent.playLocalTTS(type: .deviceGatewayRequestUnacceptable)
                default:
                    NuguCentralManager.shared.asrBeepPlayer.beep(type: .fail)
                }
            }
        default: break
        }
    }
}

// MARK: - MediaPlayerAgentDelegate

extension MainViewController: MediaPlayerAgentDelegate {
    func mediaPlayerAgentRequestContext() -> MediaPlayerAgentContext? {
        return MediaPlayerAgentContext(
            appStatus: "NORMAL",
            playerActivity: NuguCentralManager.shared.samplePlayer.state.stringValue,
            user: MediaPlayerAgentContext.User(isLogIn: "FALSE", hasVoucher: "FALSE"),
            currentSong: MediaPlayerAgentSong(category: .none, theme: nil, genre: nil, artist: ["전소미"], album: "What You Waiting For", title: "What You Waiting For", duration: "0", issueDate: nil, etc: nil),
            playlist: nil,
            toggle: MediaPlayerAgentContext.Toggle(repeat: "ONE", shuffle: "ON")
        )
    }
        
    func mediaPlayerAgentReceivePlay(payload: MediaPlayerAgentDirectivePayload.Play, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Play) -> Void)) {
        log.debug("+++")
        NuguCentralManager.shared.samplePlayer.play()
        completion(.succeeded(message: nil))
    }
    
    func mediaPlayerAgentReceiveStop(playServiceId: String, token: String, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Stop) -> Void)) {
        log.debug("+++")
        NuguCentralManager.shared.samplePlayer.stop()
        completion(.succeeded)
    }
    
    func mediaPlayerAgentReceiveSearch(payload: MediaPlayerAgentDirectivePayload.Search, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Search) -> Void)) {
        log.debug("+++")
    }
    
    func mediaPlayerAgentReceivePrevious(payload: MediaPlayerAgentDirectivePayload.Previous, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Previous) -> Void)) {
        log.debug("+++")
    }
    
    func mediaPlayerAgentReceiveNext(payload: MediaPlayerAgentDirectivePayload.Next, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Next) -> Void)) {
        log.debug("+++")
    }
    
    func mediaPlayerAgentReceiveMove(payload: MediaPlayerAgentDirectivePayload.Move, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Move) -> Void)) {
        log.debug("+++")
    }
    
    func mediaPlayerAgentReceivePause(playServiceId: String, token: String, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Pause) -> Void)) {
        log.debug("+++")
        NuguCentralManager.shared.samplePlayer.pause(temporary: false)
        completion(.succeeded(message: nil))
    }
    
    func mediaPlayerAgentReceiveResume(playServiceId: String, token: String, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Resume) -> Void)) {
        log.debug("+++")
        NuguCentralManager.shared.samplePlayer.resume()
        completion(.succeeded(message: nil))
    }
    
    func mediaPlayerAgentReceiveRewind(playServiceId: String, token: String, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Rewind) -> Void)) {
        log.debug("+++")
    }
    
    func mediaPlayerAgentReceiveToggle(payload: MediaPlayerAgentDirectivePayload.Toggle, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.Toggle) -> Void)) {
        log.debug("+++")
    }
    
    func mediaPlayerAgentReceiveGetInfo(playServiceId: String, token: String, dialogRequestId: String, completion: @escaping ((MediaPlayerAgentProcessResult.GetInfo) -> Void)) {
        log.debug("+++")
    }
}
