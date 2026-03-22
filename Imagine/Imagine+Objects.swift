//
//  Objects.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 20/3/2569 BE.
//

import UIKit
import SwiftUI
import RealityKit
import CoreText

// MARK: - Path

/// A scene object defined by an arbitrary `SwiftUI.Path`.
///
/// `PathObject` wraps any 2D path, extrudes it into a 3D mesh, and conforms to
/// ``GeometryProvider`` so it supports stroke-only and filled rendering as well as
/// ``Create`` / ``Destruct`` / ``Morph`` animations.
///
/// Create via the static factory: `.Path(myPath, color: .blue)`.
@MainActor
public final class PathObject: GeometryProvider {

	public let base_entity: Entity
	public var strokeEntity: ModelEntity?
	public var shapeEntity: ModelEntity?
	public var color: UIColor {
		didSet { updateMaterial() }
	}

	public init(_ path: SwiftUI.Path, color: UIColor = .white, depth: Float = 0.01, strokeWidth: Float = 0.02) {
		self.base_entity = Entity()
		self.strokeEntity = nil
		self.shapeEntity = nil
		self.color = color
		setupEntity(path: path, depth: depth, strokeWidth: strokeWidth, color: color)
	}
}

// MARK: - Circle

/// A scene object representing a circle (ellipse) of a given radius.
///
/// The path is constructed as an ellipse inscribed in a square centered at the origin.
/// Conforms to ``GeometryProvider`` for stroke/fill toggling and path-based animations.
///
/// Create via the static factory: `.Circle(radius: 0.5, color: .red)`.
@MainActor
public final class CircleObject: GeometryProvider {

	public let base_entity: Entity
	public var strokeEntity: ModelEntity?
	public var shapeEntity: ModelEntity?
	public var color: UIColor {
		didSet { updateMaterial() }
	}

	public let radius: Float

	public init(radius: Float = 1.0, color: UIColor = .white, depth: Float = 0.01) {
		self.radius = radius
		self.base_entity = Entity()
		self.strokeEntity = nil
		self.shapeEntity = nil
		self.color = color

		let diameter = CGFloat(radius * 2)
		let rect = CGRect(x: -CGFloat(radius), y: -CGFloat(radius), width: diameter, height: diameter)
		let path = SwiftUI.Path(ellipseIn: rect)

		setupEntity(path: path, depth: depth, strokeWidth: 0.02, color: color)
	}
}

// MARK: - Rectangle

/// A scene object representing an axis-aligned rectangle of a given width and height.
///
/// The path is constructed as a rounded rectangle (corner radius 0) centered at the origin.
/// Conforms to ``GeometryProvider`` for stroke/fill toggling and path-based animations.
///
/// Create via the static factory: `.Rectangle(width: 2, height: 1, color: .green)`.
@MainActor
public final class RectangleObject: GeometryProvider {

	public let base_entity: Entity
	public var strokeEntity: ModelEntity?
	public var shapeEntity: ModelEntity?
	public var color: UIColor {
		didSet { updateMaterial() }
	}

	public let width: Float
	public let height: Float

	public init(
		width: Float = 2.0,
		height: Float = 1.0,
		color: UIColor = .white,
		depth: Float = 0.01
	) {
		self.width = width
		self.height = height
		self.base_entity = Entity()
		self.strokeEntity = nil
		self.shapeEntity = nil
		self.color = color

		let rect = CGRect(
			x: -CGFloat(width / 2),
			y: -CGFloat(height / 2),
			width: CGFloat(width),
			height: CGFloat(height)
		)
		let path = SwiftUI.Path(roundedRect: rect, cornerRadius: 0)

		setupEntity(path: path, depth: depth, strokeWidth: 0.02, color: color)
	}
}

// MARK: - Text

/// A scene object that renders a string as extruded 3D glyphs.
///
/// Each glyph is extracted via CoreText, converted to a `SwiftUI.Path`, and given its
/// own child entity with a ``PathTrimmingComponent``. This per-glyph decomposition
/// enables the ``Write`` animation to reveal characters sequentially.
///
/// Emoji and color glyphs are rendered as textured planes instead of extruded paths.
///
/// Conforms to ``GlyphProvider`` for subscript-based glyph access and styling.
///
/// Create via the static factory: `.Text("Hello", fontSize: 72, color: .white)`.
@MainActor
public final class TextObject: GlyphProvider {

	public let base_entity: Entity
	public var color: UIColor {
		didSet { updateMaterial() }
	}

	public let text: String
	public private(set) var glyphEntities: [Entity] = []
	private let fontSize: Float
	private let extrusionDepth: Float
	private let strokeWidth: Float

	public init(
		_ text: String,
		fontSize: Float = 72,
		color: UIColor = .white,
		depth: Float = 0.01,
		strokeWidth: Float = 0.02
	) {
		self.text = text
		self.fontSize = fontSize
		self.extrusionDepth = depth
		self.strokeWidth = strokeWidth
		self.base_entity = Entity()
		self.color = color

		let ctFont = CTFontCreateWithName("Helvetica" as CFString, CGFloat(fontSize), nil)
		let glyphDataArray = GlyphData.extract(from: text, font: ctFont)

		let scaleFactor: Float = 1.0 / fontSize
		let material = UnlitMaterial(color: color)

		// Scale stroke width and depth into glyph coordinate space.
		// Glyph paths are in font-design units (~fontSize), so scene-space
		// values must be scaled up.  The entity's scale (1/fontSize) brings
		// the final visual size back to scene-space.
		let glyphStrokeWidth = strokeWidth * fontSize
		let glyphDepth = depth * fontSize

		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		let colorSIMD = SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))

		for glyphData in glyphDataArray {
			let glyphEntity = Entity()

			if glyphData.isImageGlyph {
				if let model = Self.emojiModelComponent(
					for: glyphData.character,
					fontSize: fontSize,
					advance: Float(glyphData.advance)
				) {
					glyphEntity.components.set(model)
				}

				let halfAdvance = Float(glyphData.advance) * scaleFactor / 2
				let ascenderOffset = fontSize * scaleFactor * 0.35
				glyphEntity.position = SIMD3<Float>(
					Float(glyphData.position.x) * scaleFactor + halfAdvance,
					ascenderOffset,
					0
				)
				glyphEntity.scale = SIMD3<Float>(repeating: scaleFactor)
			} else {
				// Stroke child (slightly forward to avoid z-fighting)
				let strokeChild = Entity()
				let strokeComp = PathTrimmingComponent(
					originalPath: glyphData.path,
					extrusionDepth: glyphDepth,
					strokeWidth: glyphStrokeWidth,
					currentProgress: 1.0,
					materialColor: colorSIMD
				)
				strokeChild.components.set(strokeComp)
				if let model = glyphData.path.extrudedMesh(
					depth: glyphDepth,
					strokeWidth: glyphStrokeWidth,
					material: material
				) {
					strokeChild.components.set(model)
				}
				strokeChild.position.z = glyphDepth * 0.5
				glyphEntity.addChild(strokeChild)

				// Fill child
				let fillChild = Entity()
				let fillComp = PathTrimmingComponent(
					originalPath: glyphData.path,
					extrusionDepth: glyphDepth,
					strokeWidth: glyphStrokeWidth,
					currentProgress: 1.0,
					filled: true,
					materialColor: colorSIMD
				)
				fillChild.components.set(fillComp)
				if let model = glyphData.path.extrudedMesh(
					depth: glyphDepth,
					strokeWidth: glyphStrokeWidth,
					filled: true,
					material: material
				) {
					fillChild.components.set(model)
				}
				glyphEntity.addChild(fillChild)

				glyphEntity.position = SIMD3<Float>(
					Float(glyphData.position.x) * scaleFactor,
					Float(glyphData.position.y) * scaleFactor,
					0
				)
				glyphEntity.scale = SIMD3<Float>(repeating: scaleFactor)
			}

			base_entity.addChild(glyphEntity)
			glyphEntities.append(glyphEntity)
		}

		// Center all glyphs so the text's bounding box is at origin
		let textBounds = base_entity.visualBounds(relativeTo: base_entity)
		let center = (textBounds.min + textBounds.max) / 2
		for child in base_entity.children {
			child.position.x -= center.x
			child.position.y -= center.y
		}
	}

	private static func emojiModelComponent(
		for character: String,
		fontSize: Float,
		advance: Float
	) -> ModelComponent? {
		let emojiSize = CGFloat(fontSize)
		let renderer = UIGraphicsImageRenderer(
			size: CGSize(width: emojiSize, height: emojiSize)
		)
		let image = renderer.image { _ in
			let attrs: [NSAttributedString.Key: Any] = [
				.font: UIFont.systemFont(ofSize: emojiSize)
			]
			(character as NSString).draw(at: .zero, withAttributes: attrs)
		}

		guard let cgImage = image.cgImage,
			  let texture = try? TextureResource(image: cgImage, options: .init(semantic: .color))
		else { return nil }

		var material = UnlitMaterial()
		material.color = .init(tint: .white, texture: .init(texture))
		material.blending = .transparent(opacity: 1.0)

		let mesh = MeshResource.generatePlane(width: advance, height: Float(emojiSize))
		return ModelComponent(mesh: mesh, materials: [material])
	}
}
