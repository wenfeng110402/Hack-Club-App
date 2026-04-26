//
//  InfoView.swift
//  HackClubApp
//
//  Created by 叶文峰 on 2026/4/25.
//

import SwiftUI

struct InfoView: View {
    var body: some View {
        VStack {
            Text("Version 1.3")
                .font(.subheadline)
                .padding()
                .foregroundStyle(.gray)
            
            Spacer()
        }
    }
}

#Preview {
    InfoView()
}
