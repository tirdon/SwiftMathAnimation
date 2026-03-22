//
//  Imaginable.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 20/3/2569 BE.
//

import SwiftUI
import RealityKit

// MARK: - Core Protocol

/// The base protocol for all scene objects managed by Imagine.
///
/// An `Imaginable` wraps a RealityKit `Entity` and exposes convenience accessors
/// for position, scale, rotation, and color. All concrete object types
/// (``CircleObject``, ``RectangleObject``, ``TextObject``, ``PathObject``)
/// conform to this protocol either directly or through ``GeometryProvider`` / ``GlyphProvider``.
///
/// Chainable setters (``position(_:)``, ``scale(_:)``, ``color(_:)``, etc.) return `Self`
/// for a builder-style API.
@MainActor
public protocol Imaginable: AnyObject {
	var base_entity: Entity { get }
	var color: UIColor { get set }
}

// MARK: - Computed Properties
public extension Imaginable {

	var position: SIMD3<Float> {
		get { base_entity.position }
		set { base_entity.position = newValue }
	}

	var scale: SIMD3<Float> {
		get { base_entity.scale }
		set { base_entity.scale = newValue }
	}

	var rotation: simd_quatf {
		get { base_entity.orientation }
		set { base_entity.orientation = newValue }
	}
}

// MARK: - Chainable Setters
public extension Imaginable {

	@discardableResult
	func position(_ value: SIMD3<Float>) -> Self {
		position = value
		return self
	}

	@discardableResult
	func scale(_ value: SIMD3<Float>) -> Self {
		scale = value
		return self
	}

	@discardableResult
	func rotation(_ value: simd_quatf) -> Self {
		rotation = value
		return self
	}

	@discardableResult
	func color(_ value: Color) -> Self {
		color = UIColor(value)
		return self
	}

	/// Place this object adjacent to `other` along `direction`, with `buff` gap between edges.
	@discardableResult
	func next(to other: any Imaginable, _ direction: SIMD3<Float> = .right, buff: Float = 0.25) -> Self {
		let ob = other.base_entity.visualBounds(relativeTo: other.base_entity)
		let sb = base_entity.visualBounds(relativeTo: base_entity)

		let otherCenter = (ob.min + ob.max) / 2
		let selfCenter  = (sb.min + sb.max) / 2

		// Center-align on perpendicular axes
		var pos = other.position + otherCenter - selfCenter

		// Offset along direction axis (edge-to-edge + buff)
		if direction.x > 0 {
			pos.x = other.position.x + ob.max.x + buff - sb.min.x
		} else if direction.x < 0 {
			pos.x = other.position.x + ob.min.x - buff - sb.max.x
		}

		if direction.y > 0 {
			pos.y = other.position.y + ob.max.y + buff - sb.min.y
		} else if direction.y < 0 {
			pos.y = other.position.y + ob.min.y - buff - sb.max.y
		}

		position = pos
		return self
	}

	/// Place this object against a screen edge defined by `direction`, inset by `buff`.
	@discardableResult
	func edge(_ direction: SIMD3<Float>, buff: Float = 0.5) -> Self {
		guard let bounds = Imagine.coordinateBounds else { return self }
		let sb = base_entity.visualBounds(relativeTo: base_entity)

		if direction.x > 0 {
			position.x = bounds.x.upperBound - sb.max.x - buff
		} else if direction.x < 0 {
			position.x = bounds.x.lowerBound - sb.min.x + buff
		}

		if direction.y > 0 {
			position.y = bounds.y.upperBound - sb.max.y - buff
		} else if direction.y < 0 {
			position.y = bounds.y.lowerBound - sb.min.y + buff
		}

		return self
	}
}

// MARK: - GeometryProvider Protocol

/// A protocol for ``Imaginable`` objects that are defined by a geometric `SwiftUI.Path`.
///
/// `GeometryProvider` adds support for stroke-only and filled rendering modes.
/// Conforming types (``CircleObject``, ``RectangleObject``, ``PathObject``) maintain
/// optional `strokeEntity` and `shapeEntity` children, and can be toggled between
/// stroke-only and filled presentation with ``filled(_:)``.
///
/// The ``Create`` and ``Destruct`` animations require a `GeometryProvider` so they
/// can orchestrate the stroke-draw / fill-reveal phases.
@MainActor
public protocol GeometryProvider: Imaginable {
	var strokeEntity: ModelEntity? { get set }
	var shapeEntity: ModelEntity? { get set }
}

public extension GeometryProvider {

	var isFilled: Bool { shapeEntity != nil }

	@discardableResult
	func filled(_ value: Bool = true) -> Self {
		guard value != isFilled else { return self }

		if value {
			guard let comp = base_entity.components[PathTrimmingComponent.self] else { return self }
			base_entity.components.remove(PathTrimmingComponent.self)
			base_entity.components.remove(ModelComponent.self)
			buildFilledEntities(
				path: comp.originalPath,
				depth: comp.extrusionDepth,
				strokeWidth: comp.strokeWidth,
				color: color
			)
		} else {
			guard let sEntity = strokeEntity,
				  let comp = sEntity.components[PathTrimmingComponent.self] else { return self }
			sEntity.removeFromParent()
			shapeEntity?.removeFromParent()
			strokeEntity = nil
			shapeEntity = nil
			buildStrokeOnlyEntity(
				path: comp.originalPath,
				depth: comp.extrusionDepth,
				strokeWidth: comp.strokeWidth,
				color: color
			)
		}
		return self
	}
}

// MARK: - GeometryProvider Entity Setup
extension GeometryProvider {

	func setupEntity(
		path: SwiftUI.Path,
		depth: Float,
		strokeWidth: Float,
		color: UIColor,
		filled: Bool = true
	) {
		self.color = color

		// Center the path's bounding rect at origin
		let bounds = path.boundingRect
		let centeredPath = path.applying(CGAffineTransform(
			translationX: -bounds.midX,
			y: -bounds.midY
		))

		if filled {
			buildFilledEntities(path: centeredPath, depth: depth, strokeWidth: strokeWidth, color: color)
		} else {
			buildStrokeOnlyEntity(path: centeredPath, depth: depth, strokeWidth: strokeWidth, color: color)
		}
	}

	func buildStrokeOnlyEntity(
		path: SwiftUI.Path,
		depth: Float,
		strokeWidth: Float,
		color: UIColor
	) {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		let colorSIMD = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))

		let component = PathTrimmingComponent(
			originalPath: path,
			extrusionDepth: depth,
			strokeWidth: strokeWidth,
			currentProgress: 1.0,
			materialColor: colorSIMD
		)
		base_entity.components.set(component)

		let material = UnlitMaterial(color: color)
		if let model = path.extrudedMesh(
			depth: depth,
			strokeWidth: strokeWidth,
			material: material
		) {
			base_entity.components.set(model)
		}
	}

	func buildFilledEntities(
		path: SwiftUI.Path,
		depth: Float,
		strokeWidth: Float,
		color: UIColor
	) {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		let colorSIMD = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))

		let material = UnlitMaterial(color: color)

		let sEntity = ModelEntity()
		let strokeComp = PathTrimmingComponent(
			originalPath: path,
			extrusionDepth: depth,
			strokeWidth: strokeWidth,
			currentProgress: 1.0,
			materialColor: colorSIMD
		)
		sEntity.components.set(strokeComp)
		if let model = path.extrudedMesh(
			depth: depth, strokeWidth: strokeWidth,
			material: material
		) {
			sEntity.components.set(model)
		}
		base_entity.addChild(sEntity)
		self.strokeEntity = sEntity

		let fEntity = ModelEntity()
		let fillComp = PathTrimmingComponent(
			originalPath: path,
			extrusionDepth: depth,
			strokeWidth: strokeWidth,
			currentProgress: 1.0,
			filled: true,
			materialColor: colorSIMD
		)
		fEntity.components.set(fillComp)
		if let model = path.extrudedMesh(
			depth: depth, strokeWidth: strokeWidth,
			filled: true, material: material
		) {
			fEntity.components.set(model)
		}
		base_entity.addChild(fEntity)
		self.shapeEntity = fEntity
	}

	func updateMaterial() {
		let material = UnlitMaterial(color: color)

		if let strokeEntity {
			if var model = strokeEntity.components[ModelComponent.self] {
				model.materials = [material]
				strokeEntity.components.set(model)
			}
		}
		if let shapeEntity {
			if var model = shapeEntity.components[ModelComponent.self] {
				model.materials = [material]
				shapeEntity.components.set(model)
			}
		}
		if strokeEntity == nil, var model = base_entity.components[ModelComponent.self] {
			model.materials = [material]
			base_entity.components.set(model)
		}
	}
}

// MARK: - GlyphProvider Protocol

/// A protocol for ``Imaginable`` objects whose visual content is composed of individual glyph entities.
///
/// `GlyphProvider` exposes the array of glyph child entities so that animations
/// like ``Write`` can reveal glyphs sequentially. Subscript access returns a
/// ``GlyphSlice`` for per-glyph or range-based styling.
@MainActor
public protocol GlyphProvider: Imaginable {
	var glyphEntities: [Entity] { get }
}

public extension GlyphProvider {

	subscript(range: Range<Int>) -> GlyphSlice {
		let clamped = range.clamped(to: 0..<glyphEntities.count)
		return GlyphSlice(entities: Array(glyphEntities[clamped]))
	}

	subscript(index: Int) -> GlyphSlice {
		guard glyphEntities.indices.contains(index) else {
			return GlyphSlice(entities: [])
		}
		return GlyphSlice(entities: [glyphEntities[index]])
	}

	func updateMaterial() {
		let material = UnlitMaterial(color: color)
		for entity in glyphEntities {
			if var model = entity.components[ModelComponent.self] {
				model.materials = [material]
				entity.components.set(model)
			}
		}
	}
}

// MARK: - GlyphSlice

/// A subset of glyph entities extracted from a ``GlyphProvider`` via subscript.
///
/// Setting ``color`` on a `GlyphSlice` updates the `UnlitMaterial` on all contained
/// entities, enabling per-character or per-range color customization.
@MainActor
public struct GlyphSlice {
	let entities: [Entity]

	public var color: UIColor {
		get { .white }
		set {
			let material = UnlitMaterial(color: newValue)
			for entity in entities {
				if var model = entity.components[ModelComponent.self] {
					model.materials = [material]
					entity.components.set(model)
				}
			}
		}
	}
}

// MARK: - Static Factory Methods
public extension Imaginable where Self == CircleObject {
	static func Circle(radius: Float = 1.0, color: UIColor = .white, depth: Float = 0.01) -> CircleObject {
		CircleObject(radius: radius, color: color, depth: depth)
	}
}

public extension Imaginable where Self == RectangleObject {
	static func Rectangle(width: Float = 2.0, height: Float = 1.0, color: UIColor = .white, depth: Float = 0.01) -> RectangleObject {
		RectangleObject(width: width, height: height, color: color, depth: depth)
	}
}

public extension Imaginable where Self == TextObject {
	static func Text(_ text: String, fontSize: Float = 72, color: UIColor = .white, depth: Float = 0.01) -> TextObject {
		TextObject(text, fontSize: fontSize, color: color, depth: depth)
	}
}

public extension Imaginable where Self == PathObject {
	static func Path(_ path: SwiftUI.Path, color: UIColor = .white, depth: Float = 0.01, strokeWidth: Float = 0.02) -> PathObject {
		PathObject(path, color: color, depth: depth, strokeWidth: strokeWidth)
	}
}
