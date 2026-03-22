//
//  Animations.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 19/3/2569 BE.
//

import Foundation
import SwiftUI
import RealityKit

// MARK: - Animation Protocol

/// A type that can schedule animation clips onto one or more entities.
///
/// Conforming types describe *what* should animate. The ``SceneDirector`` calls
/// ``schedule(startTime:duration:easing:)`` at the appropriate cursor position,
/// and the scheduler appends the corresponding clips to each entity's
/// ``TimelineTrackComponent``.
///
/// Built-in schedulers: ``Animate``, ``Create``, ``Destruct``, ``Morph``, ``Write``.
@MainActor
public protocol ImagineScheduler {
	var objects: [any Imaginable] { get }
	func schedule(startTime: TimeInterval,
				  duration: TimeInterval,
				  easing: AnimationEasing)
}

// MARK: - Animate

/// A general-purpose animation scheduler for transform and appearance properties.
///
/// `Animate` targets a single ``Imaginable`` object and interpolates any combination
/// of position, scale, rotation, color, and opacity over the given duration.
///
/// Use the chainable builder methods to specify targets:
/// ```swift
/// scene.play(
///     Animate(circle)
///         .position(at: SIMD3(1, 0, 0))
///         .color(to: .red),
///     duration: 1.0,
///     easing: .easeInOut
/// )
/// ```
@MainActor
public struct Animate: ImagineScheduler {

	internal unowned let object: any Imaginable

	private var targetPosition: SIMD3<Float>?
	private var targetScale: SIMD3<Float>?
	private var targetRotation: simd_quatf?
	private var targetColor: Color?
	private var targetOpacity: Float?

	public var objects: [any Imaginable] { [object] }

	public init(_ object: any Imaginable) {
		self.object = object
	}

	// MARK: Chainable property targets
	public func position(at value: SIMD3<Float>) -> Animate {
		var copy = self
		copy.targetPosition = value
		return copy
	}

	public func scale(by value: SIMD3<Float>) -> Animate {
		var copy = self
		copy.targetScale = value
		return copy
	}

	public func scale(by value: Float) -> Animate {
		scale(by: SIMD3<Float>(repeating: value))
	}

	public func rotate(to value: simd_quatf) -> Animate {
		var copy = self
		copy.targetRotation = value
		return copy
	}
	
	public func rotate(by angle: Angle, axis: SIMD3<Float>) -> Animate {
		var copy = self
		let delta = simd_quatf(angle: Float(angle.radians), axis: normalize(axis))
		copy.targetRotation = object.rotation * delta
		return copy
	}

	public func color(to value: Color) -> Animate {
		var copy = self
		copy.targetColor = value
		return copy
	}

	public func opacity(to value: Float) -> Animate {
		var copy = self
		copy.targetOpacity = value
		return copy
	}

	// MARK:  Scheduling
	public func schedule(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		let entity = object.base_entity
		var track = entity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()

		if let target = targetPosition {
			let from = track.positionClips.last?.target ?? entity.position
			track.positionClips.append(PositionClip(
				begin: startTime,
				end: startTime + duration,
				source: from,
				target: target,
				easing: easing
			))
		}

		if let target = targetScale {
			let from = track.scaleClips.last?.target ?? entity.scale
			track.scaleClips.append(ScaleClip(
				begin: startTime,
				end: startTime + duration,
				source: from,
				target: target,
				easing: easing
			))
		}

		if let target = targetRotation {
			let from = track.rotationClips.last?.target ?? entity.orientation
			track.rotationClips.append(RotationClip(
				begin: startTime,
				end: startTime + duration,
				source: from,
				target: target,
				easing: easing
			))
		}

		if let target = targetColor {
			let from: SIMD4<Float>
			if let lastClip = track.colorClips.last {
				from = lastClip.target
			} else {
				var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
				object.color.getRed(&r, green: &g, blue: &b, alpha: &a)
				from = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
			}
			var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
			
			UIColor(target).getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
			let targetSIMD = SIMD4<Float>(Float(tr), Float(tg), Float(tb), Float(ta))

			track.colorClips.append(ColorClip(
				begin: startTime,
				end: startTime + duration,
				source: from,
				target: targetSIMD,
				easing: easing
			))
		}

		if let target = targetOpacity {
			let from = track.opacityClips.last?.target
				?? (entity.components[OpacityComponent.self]?.opacity ?? 1.0)
			track.opacityClips.append(OpacityClip(
				begin: startTime,
				end: startTime + duration,
				source: from,
				target: target,
				easing: easing
			))
		}

		entity.components.set(track)
	}
}

// MARK: - Creation Animation

/// An animation scheduler that reveals a ``GeometryProvider`` object with a draw-on effect.
///
/// For stroke-only objects, the path trims from 0 to 1 over the duration.
/// For filled objects, the animation has two phases:
/// 1. The stroke outline draws on (70 % of duration).
/// 2. The stroke fades out while the fill fades in (remaining 30 %).
///
/// The object is automatically hidden (opacity 0) until the animation begins.
@MainActor
public struct Create: ImagineScheduler {

	let object: any GeometryProvider

	public var objects: [any Imaginable] { [object] }

	public init(_ object: any GeometryProvider) {
		self.object = object
	}

	public func schedule(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		if object.isFilled {
			scheduleFilled(startTime: startTime, duration: duration, easing: easing)
		} else {
			scheduleStrokeOnly(startTime: startTime, duration: duration, easing: easing)
		}
	}

	private func scheduleStrokeOnly(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		let entity = object.base_entity

		// Hide entity until Create animation begins
		entity.components.set(OpacityComponent(opacity: 0))

		if var comp = entity.components[PathTrimmingComponent.self] {
			comp.currentProgress = 0
			comp.needsRebuild = true
			entity.components.set(comp)
		}

		var track = entity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		track.opacityClips.append(OpacityClip(
			begin: startTime,
			end: startTime,
			source: 0,
			target: 1,
			easing: .linear
		))
		track.pathProgressClips.append(PathProgressClip(
			begin: startTime,
			end: startTime + duration,
			source: 0,
			target: 1,
			easing: easing
		))
		entity.components.set(track)
	}

	private func scheduleFilled(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		let base = object.base_entity
		guard let strokeEntity = object.strokeEntity,
			  let fillEntity = object.shapeEntity else { return }

		let strokeDuration = duration * 0.7

		// Hide base entity until Create animation begins
		base.components.set(OpacityComponent(opacity: 0))
		var baseTrack = base.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		baseTrack.opacityClips.append(OpacityClip(
			begin: startTime,
			end: startTime,
			source: 0,
			target: 1,
			easing: .linear
		))
		base.components.set(baseTrack)

		// Initialize: stroke at 0, fill hidden
		if var comp = strokeEntity.components[PathTrimmingComponent.self] {
			comp.currentProgress = 0
			comp.needsRebuild = true
			strokeEntity.components.set(comp)
		}

		if var comp = fillEntity.components[PathTrimmingComponent.self] {
			comp.currentProgress = 1.0
			comp.needsRebuild = true
			fillEntity.components.set(comp)
		}
		fillEntity.components.set(OpacityComponent(opacity: 0))

		// Phase 1: Draw stroke outline
		var strokeTrack = strokeEntity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		strokeTrack.pathProgressClips.append(PathProgressClip(
			begin: startTime,
			end: startTime + strokeDuration,
			source: 0,
			target: 1,
			easing: easing
		))
		strokeEntity.components.set(strokeTrack)

		// Phase 2: Fade out stroke, fade in fill
		var strokeTrack2 = strokeEntity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		strokeTrack2.opacityClips.append(OpacityClip(
			begin: startTime + strokeDuration,
			end: startTime + duration,
			source: 1,
			target: 0,
			easing: easing
		))
		strokeEntity.components.set(strokeTrack2)

		var fillTrack = fillEntity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		fillTrack.opacityClips.append(OpacityClip(
			begin: startTime + strokeDuration,
			end: startTime + duration,
			source: 0,
			target: 1,
			easing: easing
		))
		fillEntity.components.set(fillTrack)
	}
}

// MARK: - Destruction Animation

/// An animation scheduler that removes a ``GeometryProvider`` object with a reverse draw-off effect.
///
/// For stroke-only objects, the path trims from 1 back to 0 over the duration.
/// For filled objects, the animation has two phases:
/// 1. The fill fades out (30 % of duration).
/// 2. The stroke outline erases from 1 to 0 (remaining 70 %).
@MainActor
public struct Destruct: ImagineScheduler {

	let object: any GeometryProvider

	public var objects: [any Imaginable] { [object] }

	public init(_ object: any GeometryProvider) {
		self.object = object
	}

	public func schedule(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		if object.isFilled {
			scheduleFilled(startTime: startTime, duration: duration, easing: easing)
		} else {
			scheduleStrokeOnly(startTime: startTime, duration: duration, easing: easing)
		}
	}

	internal func scheduleStrokeOnly(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		let entity = object.base_entity

		var track = entity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		track.pathProgressClips.append(PathProgressClip(
			begin: startTime,
			end: startTime + duration,
			source: 1,
			target: 0,
			easing: easing
		))
		entity.components.set(track)
	}

	internal func scheduleFilled(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		guard let strokeEntity = object.strokeEntity,
			  let fillEntity = object.shapeEntity else { return }

		let fillDuration = duration * 0.3

		// Phase 1: Fade out fill
		var fillTrack = fillEntity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		fillTrack.opacityClips.append(OpacityClip(
			begin: startTime,
			end: startTime + fillDuration,
			source: 1,
			target: 0,
			easing: easing
		))
		fillEntity.components.set(fillTrack)

		// Phase 2: Reverse stroke
		var strokeTrack = strokeEntity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		strokeTrack.pathProgressClips.append(PathProgressClip(
			begin: startTime + fillDuration,
			end: startTime + duration,
			source: 1,
			target: 0,
			easing: easing
		))
		strokeEntity.components.set(strokeTrack)
	}
}

// MARK: - Transform Animation (Path Morphing)

/// An animation scheduler that morphs an entity's underlying path into a new shape.
///
/// Both the source and target paths are flattened, resampled to a matching point count,
/// and linearly interpolated per frame via ``PathMorphClip``. The entity must have a
/// ``PathTrimmingComponent`` for the morph to take effect.
@MainActor
public struct Morph: ImagineScheduler {

	let object: any Imaginable
	let targetPath: SwiftUI.Path

	public var objects: [any Imaginable] { [object] }

	public init(_ object: any Imaginable, to targetPath: SwiftUI.Path) {
		self.object = object
		self.targetPath = targetPath
	}

	public func schedule(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		let entity = object.base_entity
		guard let comp = entity.components[PathTrimmingComponent.self] else { return }

		var track = entity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
		track.pathMorphClips.append(PathMorphClip(
			begin: startTime,
			end: startTime + duration,
			source: comp.originalPath,
			target: targetPath,
			easing: easing
		))
		entity.components.set(track)
	}
}

// MARK: - Write Animation

/// An animation scheduler that reveals a ``GlyphProvider``'s text with a per-glyph handwriting effect.
///
/// Each glyph is animated sequentially with configurable overlap. Path-based glyphs
/// use a two-phase stroke-then-fill reveal (like ``Create``), while image/emoji glyphs
/// fade in.
@MainActor
public struct Write: ImagineScheduler {

	let glyphObject: any GlyphProvider

	public var objects: [any Imaginable] { [glyphObject] }

	public init(_ glyphObject: some GlyphProvider) {
		self.glyphObject = glyphObject
	}

	public func schedule(startTime: TimeInterval, duration: TimeInterval, easing: AnimationEasing) {
		let glyphEntities = glyphObject.glyphEntities
		guard !glyphEntities.isEmpty else { return }

		let overlapFactor: TimeInterval = 0.3
		let glyphCount = TimeInterval(glyphEntities.count)
		let glyphDuration = duration / (glyphCount + overlapFactor * (glyphCount - 1))

		for (index, glyphEntity) in glyphEntities.enumerated() {
			let glyphStart = startTime + TimeInterval(index) * glyphDuration * (1 - overlapFactor)

			// Find stroke/fill children (path glyph) vs direct model (emoji glyph)
			let strokeChild = glyphEntity.children.first {
				$0.components[PathTrimmingComponent.self]?.filled == false
			}
			let fillChild = glyphEntity.children.first {
				$0.components[PathTrimmingComponent.self]?.filled == true
			}

			if let strokeChild, let fillChild {
				// Path glyph: draw stroke then fill
				let strokeDuration = glyphDuration * 0.7

				// Initialize: stroke at 0, fill hidden
				if var comp = strokeChild.components[PathTrimmingComponent.self] {
					comp.currentProgress = 0
					comp.needsRebuild = true
					strokeChild.components.set(comp)
				}
				fillChild.components.set(OpacityComponent(opacity: 0))

				// Phase 1: Draw stroke
				var strokeTrack = strokeChild.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
				strokeTrack.pathProgressClips.append(PathProgressClip(
					begin: glyphStart,
					end: glyphStart + strokeDuration,
					source: 0,
					target: 1,
					easing: easing
				))
				strokeChild.components.set(strokeTrack)

				// Phase 2: Fade out stroke, fade in fill
				var strokeTrack2 = strokeChild.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
				strokeTrack2.opacityClips.append(OpacityClip(
					begin: glyphStart + strokeDuration,
					end: glyphStart + glyphDuration,
					source: 1,
					target: 0,
					easing: easing
				))
				strokeChild.components.set(strokeTrack2)

				var fillTrack = fillChild.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
				fillTrack.opacityClips.append(OpacityClip(
					begin: glyphStart + strokeDuration,
					end: glyphStart + glyphDuration,
					source: 0,
					target: 1,
					easing: easing
				))
				fillChild.components.set(fillTrack)
			} else {
				// Emoji glyph: fade in
				glyphEntity.components.set(OpacityComponent(opacity: 0))

				var track = glyphEntity.components[TimelineTrackComponent.self] ?? TimelineTrackComponent()
				track.opacityClips.append(OpacityClip(
					begin: glyphStart,
					end: glyphStart + glyphDuration,
					source: 0,
					target: 1,
					easing: easing
				))
				glyphEntity.components.set(track)
			}
		}
	}
}
