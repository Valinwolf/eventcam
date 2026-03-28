//
//  CapturedMedia.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/28/26.
//

import SwiftUI
import AVKit
import UIKit

enum CapturedMedia {
    case photo(UIImage, Date)
    case video(URL, Date)
}

enum ReviewCapture: Identifiable, Equatable {
    case photo(UIImage, Date)
    case video(URL, Date)

    var id: UUID {
        UUID()
    }

    static func == (lhs: ReviewCapture, rhs: ReviewCapture) -> Bool {
        switch (lhs, rhs) {
        case let (.photo(_, lDate), .photo(_, rDate)):
            return lDate == rDate
        case let (.video(lURL, lDate), .video(rURL, rDate)):
            return lURL == rURL && lDate == rDate
        default:
            return false
        }
    }
}

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let capture: ReviewCapture
    let onDiscard: () -> Void
    let onApprove: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                content

                VStack {
                    Spacer()

                    HStack {
                        Button {
                            player?.pause()
                            onDiscard()
                            dismiss()
                        } label: {
                            approvalIcon(systemName: "xmark")
                        }

                        Spacer()

                        Button {
                            player?.pause()
                            onApprove()
                        } label: {
                            approvalIcon(systemName: "checkmark")
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 24))
                }
            }
            .onAppear {
                if case let .video(url, _) = capture {
                    player = AVPlayer(url: url)
                    player?.seek(to: .zero)
                    player?.play()
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch capture {
        case let .photo(image, _):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

        case .video:
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            } else {
                Color.black
            }
        }
    }

    private func approvalIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.ultraThinMaterial, in: Circle())
    }
}
