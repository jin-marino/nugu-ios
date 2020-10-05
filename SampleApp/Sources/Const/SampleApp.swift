//
//  SampleApp.swift
//  SampleApp
//
//  Created by yonghoonKwon on 25/06/2019.
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

import NattyLog

// MARK: - NattyLog

let log = Natty(by: nattyConfiguration)

private var nattyConfiguration: NattyConfiguration {
    return NattyConfiguration(
        minLogLevel: .debug,
        maxDescriptionLevel: .error,
        showPersona: true,
        prefix: "FLO_SampleApp"
    )
}

// MARK: - Url

struct SampleApp {
    // Own poc_id issued from Nugu Developers site ( https://developers.nugu.co.kr/#/sdk/pocList)
    static var pocId: String {
        return "app.flo.ios"
    }
    
    static var privacyUrl: URL {
        return URL(string: "https://privacy.sktelecom.com/view.do?ctg=policy&name=policy")!
    }
    
    static let oauthRedirectUri: String = "nugu.user.67e32c41540b2e4de8c42ccd5fa59e0d://oauth_refresh"
}

// MARK: - Login Method

extension SampleApp {
    enum LoginMethod: Int, CaseIterable {
        /// Nugu App Link
        case type1 = 0
        /// Anonymous
        case type2 = 1
        
        var name: String {
            switch self {
            case .type1: return "Type 1"
            case .type2: return "Type 2"
            }
        }
    }
}

// MARK: - Sample data

extension SampleApp {
    static var loginMethod: LoginMethod? {
        return .type1
    }
    static var clientId: String? {
        return "67e32c41540b2e4de8c42ccd5fa59e0d"
    }
    static var clientSecret: String? {
        return "4cdfaf36-845e-46e8-8a56-5282fa3d0b23"
    }
    static var redirectUri: String? {
        return "nugu.user.67e32c41540b2e4de8c42ccd5fa59e0d://auth"
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    static let oauthRefresh = Notification.Name("com.skt.Romaine.oauth_refresh")
}

// MARK: - Safe Area

extension SampleApp {
    static var bottomSafeAreaHeight: CGFloat {
        guard let rootViewController = UIApplication.shared.keyWindow?.rootViewController else { return 0 }
        if #available(iOS 11.0, *) {
            return rootViewController.view.safeAreaInsets.bottom
        } else {
            return rootViewController.bottomLayoutGuide.length
        }
    }
}
