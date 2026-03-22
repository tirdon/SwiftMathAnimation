//
//  Animation.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 19/3/2569 BE.
//

import Foundation
import RealityKit
import SwiftUI

/// A collection of easing functions that control the rate of change of an animation over time.
///
/// Each case maps a normalized input `t` in `[0, 1]` to an eased output value,
/// shaping the perceived velocity of the animation.
///
/// ## Topics
/// ### Standard Easings
/// - ``linear``
/// - ``easeIn``
/// - ``easeOut``
/// - ``easeInOut``
///
/// ### Polynomial Easings
/// - ``easeInOutQuad``
/// - ``easeInOutCubic``
///
/// ### Smoothstep Easings
/// - ``smooth``
/// - ``doubleSmooth``
///
/// ### Advanced Easings
/// - ``sigmoid(steepness:)``
/// - ``expo``
/// - ``easeInElastic``
/// - ``easeOutElastic``
/// - ``wiggle(oscillations:)``
/// - ``bounce``
/// - ``spring(damping:stiffness:)``
/// - ``custom(_:)``
public enum AnimationEasing: Sendable {
	case linear
	case easeIn
	case easeOut
	case easeInOut
	case easeInOutQuad
	case easeInOutCubic
	case smooth
	case doubleSmooth
	case sigmoid(steepness: Float)
	case expo
	case easeInElastic
	case easeOutElastic
	case wiggle(oscillations: Float)
	case bounce
	case spring(damping: Float, stiffness: Float)
	case custom(@Sendable (Float) -> Float)

	//TODO: fix and clamp [0,1] and continueous
	internal func apply(_ t: Float) -> Float {
		switch self {
		case .linear:
			return t
		case .easeIn:
			return t * t
		case .easeOut:
			return t * (2 - t)
		case .easeInOut:
			return -(cos(Float.pi * t) - 1) / 2

		case .easeInOutQuad:
			return t < 0.5
				? 2 * t * t
				: 1 - pow(-2 * t + 2, 2) / 2
		case .easeInOutCubic:
			return t < 0.5
				? 4 * t * t * t
				: 1 - pow(-2 * t + 2, 3) / 2

		// Hermite smoothstep: 3t² − 2t³
		case .smooth:
			return t * t * (3 - 2 * t)

		// Perlin smootherstep: 6t⁵ − 15t⁴ + 10t³
		case .doubleSmooth:
			return t * t * t * (t * (t * 6 - 15) + 10)

		// Logistic sigmoid mapped to 0…1
		case .sigmoid(let steepness):
			let k = steepness
			let s = 1 / (1 + exp(-k * (t - 0.5)))
			let s0 = 1 / (1 + exp(k * 0.5))
			let s1 = 1 / (1 + exp(-k * 0.5))
			return (s - s0) / (s1 - s0)

		// Exponential ease-in-out
		case .expo:
			if t <= 0 { return 0 }
			if t >= 1 { return 1 }
			return t < 0.5
				? pow(2, 20 * t - 10) / 2
				: (2 - pow(2, -20 * t + 10)) / 2

		// Elastic ease in
		case .easeInElastic:
			if t <= 0 { return 0 }
			if t >= 1 { return 1 }
			let c = (2 * Float.pi) / 3
			return -pow(2, 10 * t - 10) * sin((t * 10 - 10.75) * c)

		// Elastic ease out
		case .easeOutElastic:
			if t <= 0 { return 0 }
			if t >= 1 { return 1 }
			let c = (2 * Float.pi) / 3
			return pow(2, -10 * t) * sin((t * 10 - 0.75) * c) + 1

		// Wiggle: reaches 1 at the end while oscillating along the way
		case .wiggle(let oscillations):
			let n = max(oscillations, 1)
			return t + sin(t * n * 2 * Float.pi) * (1 - t) * 0.3

		// Bounce ease out
		case .bounce:
			return Self.bounceOut(t)

		case .spring(let damping, let stiffness):
			let omega = sqrt(stiffness)
			let zeta = damping / (2 * omega)
			if zeta < 1 {
				let omegaD = omega * sqrt(1 - zeta * zeta)
				return 1 - exp(-zeta * omega * t) * (cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t))
			} else {
				return 1 - (1 + omega * t) * exp(-omega * t)
			}

		case .custom(let closure_callback):
			return closure_callback(t)
		}
	}

	private static func bounceOut(_ t: Float) -> Float {
		let n1: Float = 7.5625
		let d1: Float = 2.75
		var t = t
		if t < 1 / d1 {
			return n1 * t * t
		} else if t < 2 / d1 {
			t -= 1.5 / d1
			return n1 * t * t + 0.75
		} else if t < 2.5 / d1 {
			t -= 2.25 / d1
			return n1 * t * t + 0.9375
		} else {
			t -= 2.625 / d1
			return n1 * t * t + 0.984375
		}
	}
}

// MARK: - Shot clip

/// A time-bounded animation segment that interpolates between a source and target value.
///
/// Conforming types define a specific value type (position, scale, color, etc.) and
/// provide the begin/end times, source/target values, and an easing function.
/// The default ``progress(at:)`` implementation normalizes elapsed time and applies easing.
protocol Shot {
	associatedtype ValueType: Equatable
	var begin: TimeInterval { get }
	var end: TimeInterval { get }
	var duration: TimeInterval { get }
	var source: ValueType { get }
	var target: ValueType { get }
	var easing: AnimationEasing { get }
}

// MARK: - Progress Calculation
extension Shot {
	var duration: TimeInterval { end - begin }
	func progress(at time: TimeInterval) -> Float {
		let elapsed = time - begin
		guard duration > 0 else { return elapsed >= 0 ? 1.0 : 0.0 }
		let normalizedTime = Float(max(0, min(1, elapsed / duration)))
		return easing.apply(normalizedTime)
	}
}

// MARK: - Concrete Clips (Shot conforming)

/// A ``Shot`` that interpolates an entity's position between two `SIMD3<Float>` values.
struct PositionClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: SIMD3<Float>
	var target: SIMD3<Float>
	var easing: AnimationEasing = .linear
}

/// A ``Shot`` that interpolates an entity's scale between two `SIMD3<Float>` values.
struct ScaleClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: SIMD3<Float>
	var target: SIMD3<Float>
	var easing: AnimationEasing = .linear
}

/// A ``Shot`` that interpolates an entity's orientation between two `simd_quatf` values using spherical linear interpolation.
struct RotationClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: simd_quatf
	var target: simd_quatf
	var easing: AnimationEasing = .linear
}

/// A ``Shot`` that interpolates an entity's material color between two `SIMD4<Float>` RGBA values.
struct ColorClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: SIMD4<Float>
	var target: SIMD4<Float>
	var easing: AnimationEasing = .linear
}

/// A ``Shot`` that interpolates an entity's opacity between two `Float` values.
struct OpacityClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: Float
	var target: Float
	var easing: AnimationEasing = .linear
}

/// A ``Shot`` that interpolates a ``PathTrimmingComponent``'s `currentProgress` between two `Float` values.
///
/// Drives the path-trim reveal effect used by ``Create`` and ``Destruct`` animations.
struct PathProgressClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: Float
	var target: Float
	var easing: AnimationEasing = .linear
}

/// A ``Shot`` that morphs between two `SwiftUI.Path` shapes by flattening, resampling, and linearly interpolating their control points.
struct PathMorphClip: Shot {
	var begin: TimeInterval
	var end: TimeInterval
	var source: SwiftUI.Path
	var target: SwiftUI.Path
	var easing: AnimationEasing = .linear
}

// MARK: - Keyframe Components

/// An ECS component that stores all animation clips for an entity, organized by property track.
///
/// The ``AnimationSystem`` evaluates each track's clips every frame against the current timeline time.
struct TimelineTrackComponent: Component {
	var positionClips: [PositionClip] = []
	var scaleClips: [ScaleClip] = []
	var rotationClips: [RotationClip] = []
	var colorClips: [ColorClip] = []
	var opacityClips: [OpacityClip] = []
	var pathProgressClips: [PathProgressClip] = []
	var pathMorphClips: [PathMorphClip] = []
}

/// An ECS component that tracks per-entity playback state for the sequential timeline.
///
/// Stores the local current time, play/pause state, speed, total duration, and loop mode.
struct TimelineSequentialComponent: Component {
	var currentTime: TimeInterval = 0.0
	var isPlaying: Bool = true
	var sceneSpeed: Double = 1.0
	var totalDuration: TimeInterval = 0.0
	var mode: LoopMode = .playOnce

	/// Defines how playback behaves when reaching the end of the timeline.
	enum LoopMode { case playOnce, loop, pingpong }
}

/// An ECS component that associates an entity with a specific ``SceneDirector`` root entity.
///
/// The ``AnimationSystem`` walks up the entity hierarchy looking for this component
/// to resolve which ``TimelineManager`` provides the current time.
struct SceneMembershipComponent: Component {
	var id: Entity.ID
}

/// An ECS component that overrides the timeline's current time for a specific entity.
///
/// When `targetTime` is non-nil, the entity evaluates its animation clips at that
/// time instead of the timeline's clock — enabling scrubbing and seeking per entity.
struct ScrubOverrideComponent: Component {
	var targetTime: TimeInterval?  //nil = let timeline run
}

/// An ECS component that stores the state needed to trim, stroke, and extrude a 2D path into a 3D mesh.
///
/// The ``PathTrimmingSystem`` watches for entities whose `needsRebuild` flag is `true`,
/// then regenerates the `ModelComponent` by trimming the path at ``currentProgress``,
/// converting the stroke to a filled outline, and extruding it.
///
/// - Important: After modifying any property, set ``needsRebuild`` to `true` so the
///   system picks up the change on the next frame.
struct PathTrimmingComponent: Component {
	var originalPath: SwiftUI.Path
	var currentProgress: Float
	var extrusionDepth: Float
	var strokeWidth: Float
	var filled: Bool
	var needsRebuild: Bool
	var materialColor: SIMD4<Float>

	init(originalPath: SwiftUI.Path,
		 extrusionDepth: Float = 0.01,
		 strokeWidth: Float = 0.02,
		 currentProgress: Float = 1.0,
		 filled: Bool = false,
		 materialColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
		self.originalPath = originalPath
		self.currentProgress = currentProgress
		self.extrusionDepth = extrusionDepth
		self.strokeWidth = strokeWidth
		self.filled = filled
		self.needsRebuild = true
		self.materialColor = materialColor
	}
}

/// An ECS component that stores interaction state flags for an entity.
///
/// Used to mark entities as draggable, selectable, or holdable for gesture handling.
struct InteractivityComponent: Component {
	var isDraggable: Bool = false
	var isSelected: Bool = false
	var isHoldable: Bool = false
}

// MARK: - Animation System

/// A RealityKit `System` that evaluates all ``TimelineTrackComponent`` clips every frame.
///
/// On each `update(context:)` call the system:
/// 1. Ticks every registered ``TimelineManager`` forward by `deltaTime`.
/// 2. Iterates entities that have a ``TimelineTrackComponent``.
/// 3. Resolves the current time from the entity's ``SceneMembershipComponent``.
/// 4. Evaluates position, scale, rotation, color, opacity, path-progress, and path-morph clips.
@MainActor
final class AnimationSystem: System {

	static var managers: [Entity.ID: TimelineManager] = [:]

	static func register(_ manager: TimelineManager, for sceneID: Entity.ID) {
		managers[sceneID] = manager
	}

	private static let trackingQuery = EntityQuery(where: .has(TimelineTrackComponent.self))

	required init(scene: RealityKit.Scene) {  }

	func update(context: SceneUpdateContext) {
		let dt = context.deltaTime
		for (_, manager) in Self.managers {
			manager.tick(deltaTime: dt)
		}

		for entity in context.entities(matching: Self.trackingQuery, updatingSystemWhen: .rendering) {
			guard let track = entity.components[TimelineTrackComponent.self] else { continue }
			guard let time = Self.resolveTime(for: entity) else { continue }
			evaluatePositionClips(track.positionClips, at: time, for: entity)
			evaluateScaleClips(track.scaleClips, at: time, for: entity)
			evaluateRotationClips(track.rotationClips, at: time, for: entity)
			evaluateColorClips(track.colorClips, at: time, for: entity)
			evaluateOpacityClips(track.opacityClips, at: time, for: entity)
			evaluatePathProgressClips(track.pathProgressClips, at: time, for: entity)
			evaluatePathMorphClips(track.pathMorphClips, at: time, for: entity)
		}
	}

	// MARK: Time Resolution
	private static func resolveTime(for entity: Entity) -> TimeInterval? {
		var current: Entity? = entity
		while let e = current {
			if let membership = e.components[SceneMembershipComponent.self],
			   let manager = managers[membership.id] {
				return manager.currentTime
			}
			current = e.parent
		}
		return nil
	}

	// MARK:  Clip Evaluation
	private func evaluatePositionClips(_ clips: [PositionClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			entity.position = first.source
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			entity.position = simd_mix(clip.source, clip.target, SIMD3<Float>(repeating: t))
		}
	}

	private func evaluateScaleClips(_ clips: [ScaleClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			entity.scale = first.source
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			entity.scale = simd_mix(clip.source, clip.target, SIMD3<Float>(repeating: t))
		}
	}

	private func evaluateRotationClips(_ clips: [RotationClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			entity.orientation = first.source
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			entity.orientation = simd_slerp(clip.source, clip.target, t)
		}
	}

	private func evaluateColorClips(_ clips: [ColorClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			let color = first.source
			let uiColor = UIColor(
				red: CGFloat(color.x), green: CGFloat(color.y),
				blue: CGFloat(color.z), alpha: CGFloat(color.w)
			)
			applyMaterial(UnlitMaterial(color: uiColor), to: entity)
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			let color = simd_mix(clip.source, clip.target, SIMD4<Float>(repeating: t))
			let uiColor = UIColor(
				red: CGFloat(color.x), green: CGFloat(color.y),
				blue: CGFloat(color.z), alpha: CGFloat(color.w)
			)
			let material = UnlitMaterial(color: uiColor)
			applyMaterial(material, to: entity)
		}
	}

	private func applyMaterial(_ material: UnlitMaterial, to entity: Entity) {
		if var model = entity.components[ModelComponent.self] {
			model.materials = [material]
			entity.components.set(model)
		}
		for child in entity.children {
			applyMaterial(material, to: child)
		}
	}

	private func evaluateOpacityClips(_ clips: [OpacityClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			entity.components.set(OpacityComponent(opacity: first.source))
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			let opacity = clip.source + (clip.target - clip.source) * t
			entity.components.set(OpacityComponent(opacity: opacity))
		}
	}

	private func evaluatePathProgressClips(_ clips: [PathProgressClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			guard var comp = entity.components[PathTrimmingComponent.self] else { return }
			comp.currentProgress = first.source
			comp.needsRebuild = true
			entity.components.set(comp)
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			let progress = clip.source + (clip.target - clip.source) * t
			guard var comp = entity.components[PathTrimmingComponent.self] else { continue }
			comp.currentProgress = progress
			comp.needsRebuild = true
			entity.components.set(comp)
		}
	}

	private func evaluatePathMorphClips(_ clips: [PathMorphClip], at time: TimeInterval, for entity: Entity) {
		guard let first = clips.first else { return }
		if time < first.begin {
			guard var comp = entity.components[PathTrimmingComponent.self] else { return }
			comp.originalPath = first.source
			comp.needsRebuild = true
			entity.components.set(comp)
			return
		}
		for clip in clips where time >= clip.begin {
			let t = clip.progress(at: time)
			guard var comp = entity.components[PathTrimmingComponent.self] else { continue }
			let interpolated = SwiftUI.Path.interpolate(clip.source, clip.target, t: t)
			comp.originalPath = interpolated
			comp.needsRebuild = true
			entity.components.set(comp)
		}
	}
}

// MARK: - Path Trimming System

/// A RealityKit `System` that regenerates 3D meshes for entities with a dirty ``PathTrimmingComponent``.
///
/// Each frame the system queries entities where `needsRebuild == true`, trims the
/// stored path at the current progress, converts the stroke to a closed outline via
/// `closedForExtrusion(strokeWidth:)`, and extrudes it into a new `ModelComponent`.
///
/// A progress of `0` removes the mesh entirely; a progress of `1` uses the full original path.
@MainActor
final class PathTrimmingSystem: System {

	private static let query = EntityQuery(where: .has(PathTrimmingComponent.self))

	required init(scene: RealityKit.Scene) {}

	func update(context: SceneUpdateContext) {
		for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
			guard var comp = entity.components[PathTrimmingComponent.self] else { continue }
			guard comp.needsRebuild else { continue }

			comp.needsRebuild = false
			entity.components.set(comp)

			// Sync cached color from current ModelComponent if present
			if let model = entity.components[ModelComponent.self],
			   let mat = model.materials.first as? UnlitMaterial {
				var updated = comp
				var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
				mat.color.tint.getRed(&r, green: &g, blue: &b, alpha: &a)
				updated.materialColor = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
				entity.components.set(updated)
				comp = updated
			}

			// Progress 0 → remove mesh so nothing is visible
			if comp.currentProgress <= 0 {
				entity.components.remove(ModelComponent.self)
				continue
			}

			let trimmedPath: SwiftUI.Path
			if comp.currentProgress >= 1 {
				trimmedPath = comp.originalPath
			} else {
				trimmedPath = comp.originalPath.trimmedPath(from: 0, to: CGFloat(comp.currentProgress))
			}

			let c = comp.materialColor
			let material: any RealityKit.Material = UnlitMaterial(color: UIColor(
				red: CGFloat(c.x), green: CGFloat(c.y),
				blue: CGFloat(c.z), alpha: CGFloat(c.w)
			))

			if let model = trimmedPath.extrudedMesh(
				depth: comp.extrusionDepth,
				strokeWidth: comp.strokeWidth,
				filled: comp.filled,
				material: material
			) {
				entity.components.set(model)
			}
		}
	}
}
