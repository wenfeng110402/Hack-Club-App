//
//  HackClubAppApp.swift
//  HackClubApp
//
//  Created by 叶文峰 on 2026/4/10.
//

import SwiftUI

@main
// MARK: - App 入口
struct HackClubApp: App {
    // 这里用 AppStorage 读取本地保存的登录状态，
    // 这样 App 重启后也能记住用户是否已经登录。
    @AppStorage("isLoggedIn") private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            // 根据登录状态切换首屏：
            // 已登录就进入内容页，未登录就进入 OAuth 登录页。
            if isLoggedIn {
                ContentView()
            } else {
                OAuthView()
            }
        }
    }
}
