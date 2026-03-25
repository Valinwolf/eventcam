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
				galleryStore.addPhoto(image)
				controller.reopenCameraScreen()
			}
			.onVideoCaptured { videoURL, controller in
				galleryStore.addVideo(from: videoURL)
				controller.reopenCameraScreen()
			}
			.startSession()
	}
}
