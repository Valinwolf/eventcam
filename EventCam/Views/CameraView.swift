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

	var body: some View {
		MCamera()
			.setCloseMCameraAction {
				dismiss()
			}
			.onImageCaptured { image, controller in
				let takenAt = Date()
				galleryStore.addPhoto(image, takenAt: takenAt)
				controller.reopenCameraScreen()
			}
			.onVideoCaptured { videoURL, controller in
				let takenAt = Date()
				galleryStore.addVideo(from: videoURL, takenAt: takenAt)
				controller.reopenCameraScreen()
			}
			.startSession()
	}
}
