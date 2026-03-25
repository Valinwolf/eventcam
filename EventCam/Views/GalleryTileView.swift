//
//  GalleryTileView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI

struct GalleryTileView: View {
	let item: LocalGalleryItem
	let store: LocalGalleryStore

	var body: some View {
		ZStack(alignment: .topTrailing) {
			ZStack(alignment: .bottomTrailing) {
				if let image = store.thumbnailImage(for: item) {
					Image(uiImage: image)
						.resizable()
						.scaledToFill()
						.frame(height: 110)
						.frame(maxWidth: .infinity)
						.clipped()
						.cornerRadius(10)
				} else {
					RoundedRectangle(cornerRadius: 10)
						.fill(.gray.opacity(0.2))
						.frame(height: 110)
				}

				if item.type == .video {
					Image(systemName: "video.fill")
						.padding(6)
						.background(.ultraThinMaterial, in: Circle())
						.padding(6)
				}
			}

			Text(uploadLabel)
				.font(.caption2)
				.padding(.horizontal, 6)
				.padding(.vertical, 4)
				.background(.ultraThinMaterial, in: Capsule())
				.padding(6)
		}
	}

	private var uploadLabel: String {
		switch item.uploadState {
		case .pending: return "Pending"
		case .queued: return "Queued"
		case .uploading: return "Uploading"
		case .uploaded: return "Uploaded"
		case .failed: return "Failed"
		}
	}
}
