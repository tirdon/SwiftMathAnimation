//
//  ImagineView.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 20/3/2569 BE.
//

import SwiftUI
import RealityKit

// MARK: - ImagineScene

/// The sequential scheduling engine for an Imagine scene.
///
/// `SceneDirector` owns a root `Entity` and a ``TimelineManager``. It maintains a
/// cursor (`currentScheduleTime`) that advances as animations are scheduled, providing
/// the manim-inspired `play()` / `wait()` API:
///
/// ```swift
/// ImagineView($timeline) { scene in
///     let circle = scene.add(.Circle(radius: 0.5))
///     scene.play(Create(circle), duration: 1.0)
///     scene.wait(0.5)
///     scene.play(Animate(circle).color(to: .red), duration: 0.5)
/// }
/// ```
///
/// Objects are auto-added to the scene hierarchy when passed to ``play(_:duration:easing:)``
/// if they have no parent.
@MainActor
public final class SceneDirector {

	unowned let rootEntity: Entity
	private unowned let timeline: TimelineManager
	private var currentScheduleTime: TimeInterval = 0
	private var currentZIndex: Float = 0
	private let zStep: Float = 0.001

	init(root _Entity: Entity, timeline: TimelineManager) {
		_Entity.components.set(SceneMembershipComponent(id: _Entity.id))
		self.rootEntity = _Entity
		self.timeline = timeline
		AnimationSystem.register(timeline, for: _Entity.id)
	}

	@discardableResult
	public func add(_ object: some Imaginable) -> some Imaginable {
		currentZIndex += zStep
		object.base_entity.position.z = currentZIndex
		rootEntity.addChild(object.base_entity)
		return object
	}

	public func play(
		_ scheduler: some ImagineScheduler,
		duration: TimeInterval = 1.0,
		easing: AnimationEasing = .linear
	) {
		currentZIndex += zStep
		for object in scheduler.objects {
			if object.base_entity.parent == nil {
				object.base_entity.position.z = currentZIndex
				rootEntity.addChild(object.base_entity)
			}
		}
		scheduler.schedule(
			startTime: currentScheduleTime,
			duration: duration,
			easing: easing
		)
		currentScheduleTime += duration
		timeline.totalDuration = max(timeline.totalDuration, currentScheduleTime)
	}

	public func wait(_ duration: TimeInterval) {
		currentScheduleTime += duration
		timeline.totalDuration = max(timeline.totalDuration, currentScheduleTime)
	}
}

// MARK: - ImagineView

/// A SwiftUI view that hosts a RealityKit scene driven by Imagine's timeline engine.
///
/// `ImagineView` creates a `RealityView`, registers all ECS components and systems,
/// sets up a virtual camera, and runs the user-provided content closure through a
/// ``SceneDirector``.
///
/// Optionally call ``setCoordinateSpace(x:y:)`` to define a world-space range and
/// auto-position the camera to frame it.
///
/// ```swift
/// ImagineView($timeline) { scene in
///     scene.play(Create(.Circle()), duration: 1.0)
/// }
/// .setCoordinateSpace(x: -4...4, y: -3...3)
/// ```
public struct ImagineView: View {
	@Binding var timeline: TimelineManager
	private var scene_callback: @MainActor (SceneDirector) -> Void
	private var xRange: ClosedRange<Int>?
	private var yRange: ClosedRange<Int>?

	public init(_ timeline: Binding<TimelineManager>, content: @escaping @MainActor (SceneDirector) -> Void) {
		self._timeline = timeline
		self.scene_callback = content
	}

	public func setCoordinateSpace(x: ClosedRange<Int>, y: ClosedRange<Int>) -> ImagineView {
		var copy = self
		copy.xRange = x
		copy.yRange = y
		return copy
	}

	public var body: some View {
		RealityView { content in
			content.camera = .virtual

			// Publish coordinate bounds before running the scene callback
			if let xRange, let yRange {
				Imagine.coordinateBounds = (
					x: Float(xRange.lowerBound)...Float(xRange.upperBound),
					y: Float(yRange.lowerBound)...Float(yRange.upperBound)
				)
			}

			let rootEntity = Entity()
			let scene = SceneDirector(root: rootEntity, timeline: timeline)
			self.scene_callback(scene)
			content.add(rootEntity)

			// Set up camera if coordinate space is specified
			if let xRange, let yRange {
				let xCenter = Float(xRange.lowerBound + xRange.upperBound) / 2
				let yCenter = Float(yRange.lowerBound + yRange.upperBound) / 2
				let xWidth = Float(xRange.upperBound - xRange.lowerBound)
				let yHeight = Float(yRange.upperBound - yRange.lowerBound)
				let maxExtent = max(xWidth, yHeight)
				let fovRadians = Float(60) * .pi / 180
				let distance = (maxExtent / 2) / tan(fovRadians / 2)

				let cameraEntity = Entity()
				cameraEntity.look(at: SIMD3(xCenter, yCenter, 0), from: SIMD3(xCenter, yCenter, distance), relativeTo: nil)
				cameraEntity.components.set(PerspectiveCameraComponent())
				content.add(cameraEntity)
			}

			timeline.play()
		} update: { _ in
			// update camera state
		} placeholder: {
			
		}
		.clipped()
	}
}

// MARK: - Timeline Controller View

/// A playback-control bar providing play/pause, a scrub slider, and elapsed/total time display.
///
/// Bind to a ``TimelineManager`` to control and observe timeline playback.
struct TimelineControllerView: View {

	@Binding var timeline: TimelineManager

	init(timeline: Binding<TimelineManager>) {
		self._timeline = timeline
	}

	var body: some View {
		HStack(spacing: 16) {
			Button(action: {
				if timeline.isPlaying {
					timeline.pause()
				} else {
					timeline.play()
				}
			}) {
				Image(systemName: timeline.isPlaying ? "pause.fill" : "play.fill")
					.font(.title2)
			}

			if timeline.duration > 0 {
				let progress = Binding<Double>(
					get: { timeline.currentTime / max(timeline.duration, 0.001) },
					set: { timeline.seek(to: $0 * timeline.duration) }
				)

				Slider(value: progress, in: 0...1)

				SwiftUI.Text(formatTime(timeline.currentTime))
					.monospacedDigit()
					.foregroundStyle(.secondary)

				SwiftUI.Text("/")
					.foregroundStyle(.secondary)

				SwiftUI.Text(formatTime(timeline.duration))
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
		}
		.padding()
	}

	private func formatTime(_ time: TimeInterval) -> String {
		let seconds = Int(time) % 60
		let minutes = Int(time) / 60
		let fraction = Int((time.truncatingRemainder(dividingBy: 1)) * 10)
		return String(format: "%d:%02d.%d", minutes, seconds, fraction)
	}
}
