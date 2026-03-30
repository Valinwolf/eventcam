//
//  CameraView.swift
//  EventCam
//
//  Created by Patrick Thomas on 3/24/26.
//

import SwiftUI
import AVFoundation
import UIKit
import Combine

struct CameraView: View {
	@Environment(\.dismiss) private var dismiss
	@StateObject private var camera = CameraController()

	let onCaptureComplete: (CapturedMedia) -> Void

	@State private var baseZoomFactor: CGFloat = 1.0
	@State private var isShowingZoomSlider = false

	private let overlayButtonSize: CGFloat = 44

	var body: some View {
		GeometryReader { geo in
			ZStack {
				Color.black.ignoresSafeArea()

				CameraPreviewView(session: camera.session)
					.ignoresSafeArea()

				if camera.permissionDenied {
					permissionDeniedOverlay
				}

				liveControls(in: geo)
					.zIndex(10)

				if isShowingZoomSlider {
					zoomSliderOverlay(in: geo)
						.transition(.opacity)
						.zIndex(15)
				}
			}
			.contentShape(Rectangle())
			.gesture(modeSwipeGesture)
			.simultaneousGesture(zoomGesture)
			.onAppear {
				camera.start()
				baseZoomFactor = camera.zoomFactor
			}
			.onDisappear {
				camera.stop()
			}
			.onChange(of: camera.zoomFactor) { _, newValue in
				baseZoomFactor = newValue
			}
			.fullScreenCover(
				item: Binding(
					get: { camera.pendingReviewCapture },
					set: { newValue in
						if newValue == nil {
							camera.discardPendingCapture()
						}
					}
				)
			) { capture in
				ReviewView(
					capture: capture,
					onDiscard: {
						camera.discardPendingCapture()
					},
					onApprove: {
						if let approved = camera.approvePendingCapture() {
							onCaptureComplete(approved)
						}
					}
				)
			}
		}
	}

	// MARK: - Live Controls

	private func liveControls(in geo: GeometryProxy) -> some View {
		ZStack {
			topOverlay(topInset: geo.safeAreaInsets.top)

			VStack(spacing: 12) {
				if camera.captureMode == .video && camera.isRecording {
					HStack {
						recordingStatPill(systemName: "internaldrive", value: camera.recordingSizeText)
						Spacer()
						recordingStatPill(systemName: "timer", value: camera.recordingDurationText)
					}
					.padding(.horizontal, 4)
				}

				VStack(spacing: 12) {
					if camera.captureMode == .video && camera.isRecording {
						HStack {
							recordingStatPill(systemName: "internaldrive", value: camera.recordingSizeText)
							Spacer()
							recordingStatPill(systemName: "timer", value: camera.recordingDurationText)
						}
						.padding(.horizontal, 4)
					}

					ZStack {
						HStack {
							captureModeToggle
							Spacer()
						}

						shutterButton

						HStack {
							Spacer()
							Color.clear
								.frame(width: 44, height: 44)
						}
					}
				}
				.padding(.horizontal, 24)
				.padding(.bottom, max(geo.safeAreaInsets.bottom + 20, 34))
				.frame(maxHeight: .infinity, alignment: .bottom)
			}
			.padding(.horizontal, 24)
			.padding(.bottom, max(geo.safeAreaInsets.bottom + 20, 34))
			.frame(maxHeight: .infinity, alignment: .bottom)
		}
		.frame(width: geo.size.width, height: geo.size.height)
	}

	private func topOverlay(topInset: CGFloat) -> some View {
		HStack {
			Button {
				dismiss()
			} label: {
				overlayIcon(systemName: "xmark")
			}

			Spacer()

			HStack(spacing: 12) {
				Button {
					camera.toggleCameraPosition()
					baseZoomFactor = camera.zoomFactor
				} label: {
					overlayIcon(systemName: "camera.rotate")
				}

				Button {
					camera.cycleFlashMode()
				} label: {
					overlayIcon(systemName: flashIconName)
				}
			}
		}
		.padding(.horizontal, 24)
		.padding(.top, topInset + (overlayButtonSize * 1.3))
		.frame(maxHeight: .infinity, alignment: .top)
	}

	private var captureModeToggle: some View {
		HStack(spacing: 10) {
			modeToggleButton(
				isSelected: camera.captureMode == .photo,
				systemName: "camera"
			) {
				camera.setCaptureMode(.photo)
			}

			modeToggleButton(
				isSelected: camera.captureMode == .video,
				systemName: "video"
			) {
				camera.setCaptureMode(.video)
			}
		}
		.padding(8)
		.background(.ultraThinMaterial, in: Capsule())
	}

	private var shutterButton: some View {
		Button {
			if camera.captureMode == .photo {
				camera.capturePhoto()
			} else {
				if camera.isRecording {
					camera.stopRecording()
				} else {
					camera.startRecording()
				}
			}
		} label: {
			ZStack {
				Circle()
					.fill(.white.opacity(0.18))
					.frame(width: 92, height: 92)

				Circle()
					.stroke(.white, lineWidth: 6)
					.frame(width: 78, height: 78)

				if camera.captureMode == .video && camera.isRecording {
					RoundedRectangle(cornerRadius: 8)
						.fill(.red)
						.frame(width: 28, height: 28)
				} else {
					Circle()
						.fill(camera.captureMode == .video ? .red : .white)
						.frame(width: 62, height: 62)
				}
			}
		}
		.buttonStyle(.plain)
	}

	private func zoomSliderOverlay(in geo: GeometryProxy) -> some View {
		let totalHeight: CGFloat = 260
		let textHeight = totalHeight * 0.3
		let sliderHeight = totalHeight * 0.6
		let verticalPadding = totalHeight * 0.1

		return VStack(spacing: 0) {
			Spacer(minLength: 0)
				.frame(height: verticalPadding / 2)

			VStack {
				Text(camera.zoomText)
					.font(.caption.weight(.semibold))
					.foregroundStyle(.white)
					.monospacedDigit()
			}
			.frame(height: textHeight)

			VStack {
				Slider(
					value: Binding(
						get: { Double(camera.zoomFactor) },
						set: { camera.setZoomFactor(CGFloat($0)) }
					),
					in: Double(camera.minZoomFactor)...Double(camera.maxZoomFactor)
				)
				.rotationEffect(.degrees(-90))
				.frame(width: sliderHeight)
				.tint(.white)
			}
			.frame(height: sliderHeight)

			Spacer(minLength: 0)
				.frame(height: verticalPadding / 2)
		}
		.frame(width: 78, height: totalHeight)
		.background(.ultraThinMaterial, in: Capsule())
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.padding(.trailing, 20)
		.padding(.bottom, max(geo.safeAreaInsets.bottom + 120, 140))
	}

	private var permissionDeniedOverlay: some View {
		VStack(spacing: 12) {
			Image(systemName: "camera.fill")
				.font(.system(size: 42))
				.foregroundStyle(.white)

			Image(systemName: "slash.circle")
				.font(.system(size: 24))
				.foregroundStyle(.red)

			Text("Camera or microphone access is unavailable.")
				.foregroundStyle(.white)
				.font(.headline)
				.multilineTextAlignment(.center)

			Button("Close") {
				dismiss()
			}
			.buttonStyle(.borderedProminent)
		}
		.padding(24)
		.background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
	}

	// MARK: - Gestures

	private var zoomGesture: some Gesture {
		MagnificationGesture()
			.onChanged { value in
				if !isShowingZoomSlider {
					isShowingZoomSlider = true
				}

				let range = camera.maxZoomFactor - camera.minZoomFactor
				let target = baseZoomFactor + ((value - 1) * range * 0.02)
				let clamped = min(max(target, camera.minZoomFactor), camera.maxZoomFactor)

				camera.setZoomFactor(clamped)
			}
			.onEnded { _ in
				baseZoomFactor = camera.zoomFactor

				DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
					isShowingZoomSlider = false
				}
			}
	}

	private var modeSwipeGesture: some Gesture {
		DragGesture(minimumDistance: 30)
			.onEnded { value in
				let horizontal = value.translation.width
				let vertical = value.translation.height

				if abs(horizontal) > abs(vertical) {
					if horizontal < -40 {
						camera.setCaptureMode(.video)
					} else if horizontal > 40 {
						camera.setCaptureMode(.photo)
					}
				} else if vertical < -40 || vertical > 40 {
					camera.toggleCameraPosition()
					baseZoomFactor = camera.zoomFactor
				}
			}
	}

	// MARK: - Helpers

	private var flashIconName: String {
		switch camera.flashMode {
		case .auto:
			return "bolt.badge.a"
		case .on:
			return "bolt.fill"
		case .off:
			return "bolt.slash.fill"
		}
	}

	private func overlayIcon(systemName: String) -> some View {
		Image(systemName: systemName)
			.font(.headline)
			.foregroundStyle(.white)
			.frame(width: overlayButtonSize, height: overlayButtonSize)
			.background(.ultraThinMaterial, in: Circle())
	}

	private func modeToggleButton(
		isSelected: Bool,
		systemName: String,
		action: @escaping () -> Void
	) -> some View {
		Button(action: action) {
			Image(systemName: systemName)
				.font(.headline)
				.foregroundStyle(isSelected ? .black : .white)
				.frame(width: 40, height: 40)
				.background(
					Group {
						if isSelected {
							Circle().fill(.white)
						} else {
							Circle().fill(.clear)
						}
					}
				)
		}
		.buttonStyle(.plain)
	}

	private func recordingStatPill(systemName: String, value: String) -> some View {
		HStack(spacing: 6) {
			Image(systemName: systemName)
			Text(value)
				.monospacedDigit()
		}
		.font(.caption.weight(.semibold))
		.foregroundStyle(.white)
		.padding(.horizontal, 10)
		.padding(.vertical, 6)
		.background(.ultraThinMaterial, in: Capsule())
	}
}

// MARK: - Controller

private final class CameraController: NSObject, ObservableObject {
	enum CaptureMode {
		case photo
		case video
	}

	enum FlashMode {
		case auto
		case on
		case off

		mutating func cycle() {
			switch self {
			case .auto: self = .on
			case .on: self = .off
			case .off: self = .auto
			}
		}

		var avFlashMode: AVCaptureDevice.FlashMode {
			switch self {
			case .auto: return .auto
			case .on: return .on
			case .off: return .off
			}
		}
	}

	let session = AVCaptureSession()

	@Published var captureMode: CaptureMode = .photo
	@Published var flashMode: FlashMode = .auto
	@Published var isRecording = false
	@Published var permissionDenied = false

	@Published var minZoomFactor: CGFloat = 1.0
	@Published var maxZoomFactor: CGFloat = 5.0
	@Published var zoomFactor: CGFloat = 1.0

	@Published var recordingDurationText: String = "00:00"
	@Published var recordingSizeText: String = "0 KB"

	@Published var pendingReviewCapture: ReviewCapture?

	private let photoOutput = AVCapturePhotoOutput()
	private let movieOutput = AVCaptureMovieFileOutput()
	private let sessionQueue = DispatchQueue(label: "EventCam.Camera.Session")
	private var videoInput: AVCaptureDeviceInput?
	private var currentPosition: AVCaptureDevice.Position = .back
	private var recordingStartDate: Date?
	private var recordingStatsTimer: Timer?
	private var activeRecordingURL: URL?

	var zoomText: String {
		let safeZoom = min(max(zoomFactor, minZoomFactor), maxZoomFactor)

		if abs(safeZoom - 0.5) < 0.08 {
			return "0.5x"
		}
		if abs(safeZoom.rounded() - safeZoom) < 0.05 {
			return "\(Int(safeZoom.rounded()))x"
		}
		return String(format: "%.1fx", safeZoom)
	}

	func start() {
		Task {
			let granted = await requestPermissions()
			DispatchQueue.main.async {
				self.permissionDenied = !granted
			}

			guard granted else { return }
			self.configureSessionIfNeeded()
			self.startSession()
			self.setZoomFactor(1.0)
		}
	}

	func stop() {
		stopRecordingStatsTimer()
		sessionQueue.async { [session] in
			if session.isRunning {
				session.stopRunning()
			}
		}
	}

	func setCaptureMode(_ mode: CaptureMode) {
		guard captureMode != mode else { return }
		DispatchQueue.main.async {
			self.captureMode = mode
		}
	}

	func cycleFlashMode() {
		DispatchQueue.main.async {
			self.flashMode.cycle()
		}
	}

	func toggleCameraPosition() {
		currentPosition = (currentPosition == .back) ? .front : .back
		reconfigureInput()
	}

	func setZoomFactor(_ proposed: CGFloat) {
		sessionQueue.async {
			guard var targetDevice = self.videoInput?.device else { return }

			if self.currentPosition == .back {
				if proposed < 1.0,
				   let ultraWide = self.device(type: .builtInUltraWideCamera, position: .back) {
					if targetDevice.uniqueID != ultraWide.uniqueID {
						self.replaceVideoInput(with: ultraWide)
						targetDevice = ultraWide
					}

					let displayZoom = min(max(proposed, self.minZoomFactor), min(self.maxZoomFactor, 1.0))
					let mapped = max(ultraWide.minAvailableVideoZoomFactor, displayZoom / 0.5)
					let clampedUltra = min(max(mapped, ultraWide.minAvailableVideoZoomFactor), ultraWide.maxAvailableVideoZoomFactor)

					self.applyZoom(on: targetDevice, factor: clampedUltra)

					DispatchQueue.main.async {
						self.zoomFactor = displayZoom
					}
					return
				}

				if targetDevice.deviceType == .builtInUltraWideCamera,
				   let standardBack = self.standardBackDevice() {
					if targetDevice.uniqueID != standardBack.uniqueID {
						self.replaceVideoInput(with: standardBack)
						targetDevice = standardBack
					}
				}
			}

			let minFactor = max(targetDevice.minAvailableVideoZoomFactor, 1.0)
			let maxFactor = min(targetDevice.maxAvailableVideoZoomFactor, 10.0)
			let clamped = min(max(proposed, minFactor), maxFactor)

			self.applyZoom(on: targetDevice, factor: clamped)

			DispatchQueue.main.async {
				self.zoomFactor = clamped
			}
		}
	}

	func capturePhoto() {
		sessionQueue.async {
			guard self.pendingReviewCapture == nil else { return }

			let settings = AVCapturePhotoSettings()
			if self.photoOutput.supportedFlashModes.contains(self.flashMode.avFlashMode) {
				settings.flashMode = self.flashMode.avFlashMode
			}

			self.photoOutput.capturePhoto(with: settings, delegate: self)
		}
	}

	func startRecording() {
		let shouldEnableTorch: Bool
		switch flashMode {
		case .on:
			shouldEnableTorch = true
		case .auto, .off:
			shouldEnableTorch = false
		}

		sessionQueue.async {
			guard !self.isRecording, !self.movieOutput.isRecording, self.pendingReviewCapture == nil else { return }

			let outputURL = Self.makeTempVideoURL()
			self.activeRecordingURL = outputURL

			self.configureTorchForRecording(enabled: shouldEnableTorch)
			self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)

			DispatchQueue.main.async {
				self.isRecording = true
				self.recordingStartDate = Date()
				self.recordingDurationText = "00:00"
				self.recordingSizeText = "0 KB"
				self.startRecordingStatsTimer()
			}
		}
	}

	func stopRecording() {
		sessionQueue.async {
			guard self.movieOutput.isRecording else { return }
			self.movieOutput.stopRecording()
		}
	}

	func discardPendingCapture() {
		if case let .video(url, _) = pendingReviewCapture {
			try? FileManager.default.removeItem(at: url)
		}

		DispatchQueue.main.async {
			self.pendingReviewCapture = nil
		}
	}

	func approvePendingCapture() -> CapturedMedia? {
		guard let pendingReviewCapture else { return nil }

		let result: CapturedMedia
		switch pendingReviewCapture {
		case let .photo(image, takenAt):
			result = .photo(image, takenAt)
		case let .video(url, takenAt):
			result = .video(url, takenAt)
		}

		DispatchQueue.main.async {
			self.pendingReviewCapture = nil
		}

		return result
	}

	private func requestPermissions() async -> Bool {
		let cameraGranted: Bool
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .authorized:
			cameraGranted = true
		case .notDetermined:
			cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
		default:
			cameraGranted = false
		}

		let micGranted: Bool
		switch AVCaptureDevice.authorizationStatus(for: .audio) {
		case .authorized:
			micGranted = true
		case .notDetermined:
			micGranted = await AVCaptureDevice.requestAccess(for: .audio)
		default:
			micGranted = false
		}

		return cameraGranted && micGranted
	}

	private func configureSessionIfNeeded() {
		sessionQueue.async {
			guard self.videoInput == nil else { return }

			self.session.beginConfiguration()
			self.session.sessionPreset = .high

			defer {
				self.session.commitConfiguration()
				self.syncZoomBounds()
			}

			guard let videoDevice = self.standardBackDevice() else { return }

			do {
				let videoInput = try AVCaptureDeviceInput(device: videoDevice)
				if self.session.canAddInput(videoInput) {
					self.session.addInput(videoInput)
					self.videoInput = videoInput
				}
			} catch {
				print("Failed to create video input:", error)
			}

			if let audioDevice = AVCaptureDevice.default(for: .audio) {
				do {
					let audioInput = try AVCaptureDeviceInput(device: audioDevice)
					if self.session.canAddInput(audioInput) {
						self.session.addInput(audioInput)
					}
				} catch {
					print("Failed to create audio input:", error)
				}
			}

			if self.session.canAddOutput(self.photoOutput) {
				self.session.addOutput(self.photoOutput)
			}

			if self.session.canAddOutput(self.movieOutput) {
				self.session.addOutput(self.movieOutput)
			}
		}
	}

	private func startSession() {
		sessionQueue.async { [session] in
			guard !session.isRunning else { return }
			session.startRunning()
		}
	}

	private func reconfigureInput() {
		sessionQueue.async {
			guard let newDevice = self.bestDevice(for: self.currentPosition) else { return }

			self.session.beginConfiguration()

			if let currentInput = self.videoInput {
				self.session.removeInput(currentInput)
				self.videoInput = nil
			}

			do {
				let newInput = try AVCaptureDeviceInput(device: newDevice)
				if self.session.canAddInput(newInput) {
					self.session.addInput(newInput)
					self.videoInput = newInput
				}
			} catch {
				print("Failed to swap camera input:", error)
			}

			self.session.commitConfiguration()
			self.syncZoomBounds()
			self.setZoomFactor(1.0)
		}
	}

	private func bestDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
		if position == .front {
			return device(type: .builtInTrueDepthCamera, position: .front)
				?? device(type: .builtInWideAngleCamera, position: .front)
		}

		return standardBackDevice()
	}

	private func standardBackDevice() -> AVCaptureDevice? {
		device(type: .builtInTripleCamera, position: .back)
			?? device(type: .builtInDualWideCamera, position: .back)
			?? device(type: .builtInDualCamera, position: .back)
			?? device(type: .builtInWideAngleCamera, position: .back)
			?? device(type: .builtInUltraWideCamera, position: .back)
	}

	private func device(type: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position) -> AVCaptureDevice? {
		let discovery = AVCaptureDevice.DiscoverySession(
			deviceTypes: [type],
			mediaType: .video,
			position: position
		)
		return discovery.devices.first
	}

	private func replaceVideoInput(with device: AVCaptureDevice) {
		session.beginConfiguration()
		if let currentInput = videoInput {
			session.removeInput(currentInput)
		}

		do {
			let newInput = try AVCaptureDeviceInput(device: device)
			if session.canAddInput(newInput) {
				session.addInput(newInput)
				videoInput = newInput
			}
		} catch {
			print("Failed to replace video input:", error)
		}
		session.commitConfiguration()
		syncZoomBounds()
	}

	private func applyZoom(on device: AVCaptureDevice, factor: CGFloat) {
		do {
			try device.lockForConfiguration()
			device.videoZoomFactor = factor
			device.unlockForConfiguration()
		} catch {
			print("Failed to apply zoom:", error)
		}
	}

	private func syncZoomBounds() {
		guard let device = videoInput?.device else { return }

		let minFactor: CGFloat
		let displayedZoom: CGFloat

		if currentPosition == .back, hasUltraWideBackCamera {
			minFactor = 0.5
			displayedZoom = device.deviceType == .builtInUltraWideCamera ? 0.5 : 1.0
		} else {
			minFactor = max(device.minAvailableVideoZoomFactor, 1.0)
			displayedZoom = 1.0
		}

		let maxFactor = min(device.maxAvailableVideoZoomFactor, 10.0)

		DispatchQueue.main.async {
			self.minZoomFactor = minFactor
			self.maxZoomFactor = maxFactor
			self.zoomFactor = displayedZoom
		}
	}

	private var hasUltraWideBackCamera: Bool {
		let discovery = AVCaptureDevice.DiscoverySession(
			deviceTypes: [.builtInUltraWideCamera],
			mediaType: .video,
			position: .back
		)
		return !discovery.devices.isEmpty
	}

	private func configureTorchForRecording(enabled: Bool) {
		guard let device = videoInput?.device, device.hasTorch else { return }

		do {
			try device.lockForConfiguration()
			if enabled {
				try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
			} else {
				device.torchMode = .off
			}
			device.unlockForConfiguration()
		} catch {
			print("Failed to configure torch:", error)
		}
	}

	private func startRecordingStatsTimer() {
		stopRecordingStatsTimer()

		recordingStatsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
			guard let self else { return }

			if let start = self.recordingStartDate {
				let elapsed = Date().timeIntervalSince(start)
				self.recordingDurationText = Self.formatDuration(elapsed)
			}

			if let activeRecordingURL = self.activeRecordingURL,
			   let attrs = try? FileManager.default.attributesOfItem(atPath: activeRecordingURL.path),
			   let fileSize = attrs[.size] as? NSNumber {
				self.recordingSizeText = Self.formatFileSize(fileSize.int64Value)
			}
		}
	}

	private func stopRecordingStatsTimer() {
		recordingStatsTimer?.invalidate()
		recordingStatsTimer = nil
	}

	private static func formatDuration(_ duration: TimeInterval) -> String {
		let total = Int(duration.rounded(.down))
		let minutes = total / 60
		let seconds = total % 60
		return String(format: "%02d:%02d", minutes, seconds)
	}

	private static func formatFileSize(_ bytes: Int64) -> String {
		let formatter = ByteCountFormatter()
		formatter.allowedUnits = [.useKB, .useMB]
		formatter.countStyle = .file
		return formatter.string(fromByteCount: bytes)
	}

	private static func makeTempVideoURL() -> URL {
		FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
			.appendingPathExtension("mov")
	}
}

extension CameraController: AVCapturePhotoCaptureDelegate {
	nonisolated func photoOutput(
		_ output: AVCapturePhotoOutput,
		didFinishProcessingPhoto photo: AVCapturePhoto,
		error: Error?
	) {
		if let error {
			print("Photo capture failed:", error)
			return
		}

		guard let data = photo.fileDataRepresentation(),
			  let image = UIImage(data: data) else {
			print("Photo capture failed: missing image data")
			return
		}

		let takenAt = Date()

		DispatchQueue.main.async {
			self.pendingReviewCapture = .photo(image, takenAt)
		}
	}
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
	nonisolated func fileOutput(
		_ output: AVCaptureFileOutput,
		didFinishRecordingTo outputFileURL: URL,
		from connections: [AVCaptureConnection],
		error: Error?
	) {
		sessionQueue.async {
			self.configureTorchForRecording(enabled: false)
		}

		DispatchQueue.main.async {
			self.stopRecordingStatsTimer()
			self.isRecording = false
		}

		if let error {
			print("Video recording failed:", error)
			try? FileManager.default.removeItem(at: outputFileURL)
			return
		}

		let takenAt = Date()

		DispatchQueue.main.async {
			self.pendingReviewCapture = .video(outputFileURL, takenAt)
		}
	}
}

// MARK: - Preview Bridge

private struct CameraPreviewView: UIViewRepresentable {
	let session: AVCaptureSession

	func makeUIView(context: Context) -> PreviewUIView {
		let view = PreviewUIView()
		view.videoPreviewLayer.session = session
		view.videoPreviewLayer.videoGravity = .resizeAspectFill
		return view
	}

	func updateUIView(_ uiView: PreviewUIView, context: Context) {
		uiView.videoPreviewLayer.session = session
	}
}

private final class PreviewUIView: UIView {
	override class var layerClass: AnyClass {
		AVCaptureVideoPreviewLayer.self
	}

	var videoPreviewLayer: AVCaptureVideoPreviewLayer {
		guard let layer = layer as? AVCaptureVideoPreviewLayer else {
			fatalError("Expected AVCaptureVideoPreviewLayer")
		}
		return layer
	}
}
