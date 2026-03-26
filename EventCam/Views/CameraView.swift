//
//  CameraView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI
import MijickCamera
import UIKit

struct CameraView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject var galleryStore: LocalGalleryStore

	let reopenAfterCapture: () -> Void

	var body: some View {
		MCamera()
			.setCloseMCameraAction {
				dismiss()
			}
			.onImageCaptured { image, _ in
				let takenAt = Date()
				galleryStore.addPhoto(image, takenAt: takenAt)
				reopen()
			}
			.onVideoCaptured { videoURL, _ in
				let takenAt = Date()
				galleryStore.addVideo(from: videoURL, takenAt: takenAt)
				reopen()
			}
			.startSession()
	}

	private func reopen() {
		dismiss()

		//DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
		//	reopenAfterCapture()
		//}
	}
}
