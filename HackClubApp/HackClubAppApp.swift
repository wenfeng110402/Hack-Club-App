//
//  HackClubAppApp.swift
//  HackClubApp
//
//  Created by 叶文峰 on 2026/4/10.
//

import SwiftUI

@main
// MARK: - App 入口（真正启动第一个运行的地方）
struct HackClubApp: App {
    // 读取本地登录状态
    @AppStorage("isLoggedIn") private var isLoggedIn = false

    var body: some Scene {
        WindowGroup {
            // 核心逻辑：
            // 已登录 → 主页
            // 未登录 → 登录页
            if isLoggedIn {
                ContentView()
            } else {
                OAuthView()
            }
        }
    }
}
