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

	let onCaptureComplete: (CapturedMedia) -> Void

	@State private var pendingCapture: CapturedMedia?

	enum CapturedMedia {
		case photo(UIImage, Date)
		case video(URL, Date)
	}

	var body: some View {
		MCamera()
			.setCloseMCameraAction {
				dismiss()
			}
			.onImageCaptured { image, _ in
				pendingCapture = .photo(image, Date())
				dismiss()
			}
			.onVideoCaptured { videoURL, _ in
				pendingCapture = .video(videoURL, Date())
				dismiss()
			}
			.startSession()
			.onDisappear {
				guard let pendingCapture else { return }
				self.pendingCapture = nil
				onCaptureComplete(pendingCapture)
			}
	}
}
