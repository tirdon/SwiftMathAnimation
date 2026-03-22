//
//  Imagine.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 19/3/2569 BE.
//

import SwiftUI
import RealityKit

/// The top-level namespace for the Imagine animation library.
///
/// `Imagine` is an uninhabited enum used purely as a namespace for
/// static helpers such as ``registerProgram()`` and coordinate-space state.
/// Object typealiases (e.g. `Imagine.Circle`, `Imagine.Rectangle`) are provided
/// via static factory methods on ``Imaginable``.
@MainActor
public enum Imagine {  }

@MainActor
public extension Imagine {
	static func registerProgram() {
		TimelineTrackComponent.registerComponent()
		TimelineSequentialComponent.registerComponent()
		SceneMembershipComponent.registerComponent()
		ScrubOverrideComponent.registerComponent()
		PathTrimmingComponent.registerComponent()
		InteractivityComponent.registerComponent()

		AnimationSystem.registerSystem()
		PathTrimmingSystem.registerSystem()
	}
}

// MARK: - Timeline

/// The central clock that drives all animation playback in an Imagine scene.
///
/// `TimelineManager` tracks the current time, play/pause state, speed, and loop mode.
/// Each frame, the ``AnimationSystem`` calls ``tick(deltaTime:)`` to advance the clock,
/// and all ``TimelineTrackComponent`` clips are evaluated against ``currentTime``.
///
/// Use ``play()``, ``pause()``, and ``seek(to:)`` to control playback from the UI.
///
/// ## Topics
/// ### Playback Control
/// - ``play()``
/// - ``pause()``
/// - ``seek(to:)``
///
/// ### State
/// - ``currentTime``
/// - ``isPlaying``
/// - ``duration``
/// - ``playbackSpeed``
/// - ``loopMode``
@MainActor @Observable
public final class TimelineManager {

	/// Defines how playback behaves when reaching the timeline boundaries.
	public enum LoopMode { case playOnce, loop, pingpong }

	public private(set) var currentTime: TimeInterval = 0
	public private(set) var isPlaying: Bool = false
	public var loopMode: LoopMode = .playOnce
	public var playbackSpeed: Double = 1.0
	internal var totalDuration: TimeInterval = 0
	private var direction: Double = 1.0

	public var duration: TimeInterval { totalDuration }

	public init() {}

	public func play() {
		guard !isPlaying else { return }
		isPlaying = true
	}

	public func pause() {
		isPlaying = false
	}

	public func seek(to time: TimeInterval) {
		currentTime = max(0, min(time, totalDuration))
	}

	internal func tick(deltaTime: TimeInterval) {
		guard isPlaying else { return }
		currentTime += deltaTime * playbackSpeed * direction

		guard totalDuration > 0 else { return }

		switch loopMode {
		case .playOnce:
			if currentTime >= totalDuration {
				currentTime = totalDuration
				pause()
			} else if currentTime < 0 {
				currentTime = 0
				pause()
			}
		case .loop:
			if currentTime >= totalDuration {
				currentTime = currentTime.truncatingRemainder(dividingBy: totalDuration)
			} else if currentTime < 0 {
				currentTime = totalDuration + currentTime.truncatingRemainder(dividingBy: totalDuration)
			}
		case .pingpong:
			if currentTime >= totalDuration {
				direction = -direction
				currentTime = totalDuration
			} else if currentTime < 0 {
				direction = -direction
				currentTime = 0
			}
		}
	}
}

// MARK: - Camera Controller

/// A convenience wrapper around a RealityKit `PerspectiveCamera` entity.
///
/// Provides imperative methods to set the camera's position, look-at target,
/// and field of view. Used internally by ``ImagineView`` when a coordinate space is configured.
@MainActor
public final class CameraController {

	unowned let camera_entity: Entity

	init() {
		self.camera_entity = Entity()
		let camera = PerspectiveCamera()
		camera_entity.addChild(camera)
	}

	func set(position: SIMD3<Float>) {
		camera_entity.position = position
	}

	func look(at target: SIMD3<Float>) {
		camera_entity.look(at: target, from: camera_entity.position, relativeTo: nil)
	}

	func set(FoV degrees: Float) {
		guard let camera = camera_entity.children.first else { return }
		var perspective = PerspectiveCameraComponent()
		perspective.fieldOfViewInDegrees = degrees
		camera.components.set(perspective)
	}
}

// MARK: - Coordinate Space
@MainActor
public extension Imagine {
	internal(set) static var coordinateBounds: (x: ClosedRange<Float>, y: ClosedRange<Float>)?
}

// MARK: - Direction Constants
public extension SIMD3 where Scalar == Float {
	static var origin: SIMD3<Float>  { .init(0,  0, 0) }
	static var up: SIMD3<Float>      { .init(0,  1, 0) }
	static var down: SIMD3<Float>    { .init(0, -1, 0) }
	static var left: SIMD3<Float>    { .init(-1, 0, 0) }
	static var right: SIMD3<Float>   { .init(1,  0, 0) }
	static var forward: SIMD3<Float> { .init(0,  0,-1) }
	static var back: SIMD3<Float>    { .init(0,  0, 1) }
}

public extension Numeric where Self == Double {
	var i: SIMD3<Float> { SIMD3<Float>(Float(self), 0,   0   ) }
	var j: SIMD3<Float> { SIMD3<Float>(0,    Float(self),0   ) }
	var k: SIMD3<Float> { SIMD3<Float>(0, 	 0,   Float(self)) }
}

public extension Numeric where Self == Float {
	var i: SIMD3<Float> { SIMD3<Float>(Float(self), 0,   0   ) }
	var j: SIMD3<Float> { SIMD3<Float>(0,    Float(self),0   ) }
	var k: SIMD3<Float> { SIMD3<Float>(0, 	 0,   Float(self)) }
}

public extension Numeric where Self == Int {
	var i: SIMD3<Float> { SIMD3<Float>(Float(self), 0,   0   ) }
	var j: SIMD3<Float> { SIMD3<Float>(0,    Float(self),0   ) }
	var k: SIMD3<Float> { SIMD3<Float>(0, 	 0,   Float(self)) }
}
