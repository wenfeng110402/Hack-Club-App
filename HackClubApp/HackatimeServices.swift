//
//  HackatimeServices.swift
//  HackClubApp
//
//  Created by 叶文峰 on 2026/4/26.
//

import Foundation
import SwiftUI
import AuthenticationServices

// MARK: - Hackatime 页面
struct HackatimeView: View {
    var body: some View {
        ZStack {
            AppPalette.background.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "timer")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(hex: 0x58A6FF))
                
                VStack(spacing: 8) {
                    Text("Hackatime")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Login to get your Hackatime stats")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                // 未登录状态下的登录按钮
                Button {
                    // TODO: 在这里触发 Hackatime OAuth 流程
                    print("Start Hackatime OAuth")
                } label: {
                    Text("Login with Hackatime")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: 0x58A6FF))
                        .cornerRadius(16)
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                
                Spacer()
            }
            .padding(.top, 60)
        }
        .navigationTitle("Hackatime")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#Preview {
    HackatimeView()
}
