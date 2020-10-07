//
//  SamplePlayer.swift
//  SampleApp
//
//  Created by jin kim on 2019/12/09.
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

final class SamplePlayer {
    
    enum State {
        case stopped
        case playing
        case paused(temporary: Bool)
        
        var stringValue: String {
            switch self {
            case .stopped:
             return "STOPPED"
            case .playing:
             return "PLAYING"
            case .paused(let temporary):
                return temporary ? "PLAYING" : "PAUSED"
            }
        }
    }
    
    private var player: AVPlayer?
    
    var state: State = .stopped
    
    func play() {
        guard let url = Bundle.main.url(forResource: "LUV", withExtension: "mp3") else {
            log.error("Can't find sound file")
            state = .stopped
            return
        }
        player = AVPlayer(url: url)
        player?.play()
        state = .playing
    }
    
    func pause(temporary: Bool) {
        player?.pause()
        state = .paused(temporary: temporary)
    }
    
    func resume() {
        player?.play()
        state = .playing
    }
    
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        state = .stopped
    }
}
