//
//  GeometricObject.swift
//  Imagine
//
//  Created by Thiradon Mueangmo on 20/3/2569 BE.
//

import SwiftUI
import CoreText
import RealityKit

// MARK: - Path Extensions

@MainActor
extension SwiftUI.Path {
	func extrudedMesh(
		depth: Float,
		strokeWidth: Float,
		filled: Bool = false,
		material: any RealityKit.Material
	) -> ModelComponent? {
		let closedPath = filled ? self : self.closedForExtrusion(strokeWidth: strokeWidth)

		var options = MeshResource.ShapeExtrusionOptions()
		options.extrusionMethod = .linear(depth: depth)

		do {
			let mesh = try MeshResource(extruding: closedPath, extrusionOptions: options)
			return ModelComponent(mesh: mesh, materials: [material])
		} catch {
			return nil
		}
	}

	func closedForExtrusion(strokeWidth: Float) -> SwiftUI.Path {
		let style = StrokeStyle(
			lineWidth: CGFloat(strokeWidth),
			lineCap: .round,
			lineJoin: .round
		)
		return strokedPath(style)
	}

	var pathLength: CGFloat {
		var length: CGFloat = 0
		var currentPoint: CGPoint = .zero
		var startPoint: CGPoint = .zero

		forEach { element in
			switch element {
			case .move(let to):
				currentPoint = to
				startPoint = to
			case .line(let to):
				length += Self.distance(from: currentPoint, to: to)
				currentPoint = to
			case .quadCurve(let to, let control):
				length += Self.approximateQuadLength(from: currentPoint, control: control, to: to)
				currentPoint = to
			case .curve(let to, let control1, let control2):
				length += Self.approximateCubicLength(from: currentPoint, c1: control1, c2: control2, to: to)
				currentPoint = to
			case .closeSubpath:
				length += Self.distance(from: currentPoint, to: startPoint)
				currentPoint = startPoint
			}
		}
		return length
	}

	static func interpolate(_ pathA: SwiftUI.Path, _ pathB: SwiftUI.Path, t: Float) -> SwiftUI.Path {
		let pointsA = flattenPath(pathA)
		let pointsB = flattenPath(pathB)

		guard !pointsA.isEmpty, !pointsB.isEmpty else {
			return t < 0.5 ? pathA : pathB
		}

		let count = max(pointsA.count, pointsB.count)
		let resampledA = resample(pointsA, count: count)
		let resampledB = resample(pointsB, count: count)

		var result = SwiftUI.Path()
		let cgt = CGFloat(t)

		for i in 0..<count {
			let x = resampledA[i].x + (resampledB[i].x - resampledA[i].x) * cgt
			let y = resampledA[i].y + (resampledB[i].y - resampledA[i].y) * cgt
			let point = CGPoint(x: x, y: y)

			if i == 0 {
				result.move(to: point)
			} else {
				result.addLine(to: point)
			}
		}
		result.closeSubpath()
		return result
	}

	// MARK: - Private Helpers

	private static func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
		hypot(b.x - a.x, b.y - a.y)
	}

	private static func approximateQuadLength(from p0: CGPoint, control: CGPoint, to p2: CGPoint, steps: Int = 16) -> CGFloat {
		var length: CGFloat = 0
		var prev = p0
		for i in 1...steps {
			let t = CGFloat(i) / CGFloat(steps)
			let mt = 1 - t
			let x = mt * mt * p0.x + 2 * mt * t * control.x + t * t * p2.x
			let y = mt * mt * p0.y + 2 * mt * t * control.y + t * t * p2.y
			let curr = CGPoint(x: x, y: y)
			length += distance(from: prev, to: curr)
			prev = curr
		}
		return length
	}

	private static func approximateCubicLength(from p0: CGPoint, c1: CGPoint, c2: CGPoint, to p3: CGPoint, steps: Int = 16) -> CGFloat {
		var length: CGFloat = 0
		var prev = p0
		for i in 1...steps {
			let t = CGFloat(i) / CGFloat(steps)
			let mt = 1 - t
			let x = mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p3.x
			let y = mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p3.y
			let curr = CGPoint(x: x, y: y)
			length += distance(from: prev, to: curr)
			prev = curr
		}
		return length
	}

	private static func flattenPath(_ path: SwiftUI.Path, steps: Int = 16) -> [CGPoint] {
		var points: [CGPoint] = []
		var currentPoint: CGPoint = .zero

		path.forEach { element in
			switch element {
			case .move(let to):
				points.append(to)
				currentPoint = to
			case .line(let to):
				points.append(to)
				currentPoint = to
			case .quadCurve(let to, let control):
				for i in 1...steps {
					let t = CGFloat(i) / CGFloat(steps)
					let mt = 1 - t
					let x = mt * mt * currentPoint.x + 2 * mt * t * control.x + t * t * to.x
					let y = mt * mt * currentPoint.y + 2 * mt * t * control.y + t * t * to.y
					points.append(CGPoint(x: x, y: y))
				}
				currentPoint = to
			case .curve(let to, let control1, let control2):
				for i in 1...steps {
					let t = CGFloat(i) / CGFloat(steps)
					let mt = 1 - t
					let x = mt * mt * mt * currentPoint.x + 3 * mt * mt * t * control1.x + 3 * mt * t * t * control2.x + t * t * t * to.x
					let y = mt * mt * mt * currentPoint.y + 3 * mt * mt * t * control1.y + 3 * mt * t * t * control2.y + t * t * t * to.y
					points.append(CGPoint(x: x, y: y))
				}
				currentPoint = to
			case .closeSubpath:
				break
			}
		}
		return points
	}

	private static func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
		guard points.count >= 2 else {
			return Array(repeating: points.first ?? .zero, count: count)
		}

		var distances: [CGFloat] = [0]
		for i in 1..<points.count {
			distances.append(distances[i - 1] + distance(from: points[i - 1], to: points[i]))
		}

		let totalLength = distances.last!
		guard totalLength > 0 else {
			return Array(repeating: points[0], count: count)
		}

		var result: [CGPoint] = []
		for i in 0..<count {
			let targetDist = totalLength * CGFloat(i) / CGFloat(count - 1)

			var segIndex = 0
			for j in 1..<distances.count {
				if distances[j] >= targetDist {
					segIndex = j - 1
					break
				}
				segIndex = j - 1
			}

			let segLen = distances[segIndex + 1] - distances[segIndex]
			let localT = segLen > 0 ? (targetDist - distances[segIndex]) / segLen : 0

			let x = points[segIndex].x + (points[segIndex + 1].x - points[segIndex].x) * localT
			let y = points[segIndex].y + (points[segIndex + 1].y - points[segIndex].y) * localT
			result.append(CGPoint(x: x, y: y))
		}
		return result
	}
}

// MARK: - GlyphData

/// Extracted data for a single glyph from a CoreText layout pass.
///
/// A `GlyphData` value holds either a vector path for a standard glyph or a
/// character string for an image/emoji glyph, along with the glyph's position
/// and advance width within the text line.
///
/// Use ``extract(from:font:)`` to obtain an array of glyph data from a string.
struct GlyphData: Sendable {
	let path: SwiftUI.Path
	let position: CGPoint
	let advance: CGFloat
	let isImageGlyph: Bool
	let character: String

	init(path: SwiftUI.Path, position: CGPoint, advance: CGFloat) {
		self.path = path
		self.position = position
		self.advance = advance
		self.isImageGlyph = false
		self.character = ""
	}

	init(character: String, position: CGPoint, advance: CGFloat) {
		self.path = SwiftUI.Path()
		self.position = position
		self.advance = advance
		self.isImageGlyph = true
		self.character = character
	}

	static func extract(from string: String, font: CTFont) -> [GlyphData] {
		let attributedString = CFAttributedStringCreate(
			nil,
			string as CFString,
			[kCTFontAttributeName: font] as CFDictionary
		)!
		let line = CTLineCreateWithAttributedString(attributedString)
		let runs = CTLineGetGlyphRuns(line) as! [CTRun]

		var glyphs: [GlyphData] = []
		var xOffset: CGFloat = 0

		for run in runs {
			let runAttrs = CTRunGetAttributes(run) as NSDictionary
			let glyphFont: CTFont
			if let f = runAttrs[kCTFontAttributeName] {
				glyphFont = (f as! CTFont)
			} else {
				glyphFont = font
			}

			let count = CTRunGetGlyphCount(run)
			var advances = [CGSize](repeating: .zero, count: count)
			CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)

			let traits = CTFontGetSymbolicTraits(glyphFont)
			if traits.contains(.traitColorGlyphs) {
				var stringIndices = [CFIndex](repeating: 0, count: count)
				CTRunGetStringIndices(run, CFRange(location: 0, length: count), &stringIndices)

				let runRange = CTRunGetStringRange(run)
				let nsString = string as NSString

				for i in 0..<count {
					let startIdx = stringIndices[i]
					let endIdx = (i + 1 < count)
						? stringIndices[i + 1]
						: (runRange.location + runRange.length)
					let charStr = nsString.substring(
						with: NSRange(location: startIdx, length: endIdx - startIdx)
					)

					let data = GlyphData(
						character: charStr,
						position: CGPoint(x: xOffset, y: 0),
						advance: advances[i].width
					)
					glyphs.append(data)
					xOffset += advances[i].width
				}
				continue
			}

			var glyphIDs = [CGGlyph](repeating: 0, count: count)
			CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphIDs)

			for i in 0..<count {
				if let cgPath = CTFontCreatePathForGlyph(glyphFont, glyphIDs[i], nil) {
					let swiftPath = SwiftUI.Path(cgPath)
					let data = GlyphData(
						path: swiftPath,
						position: CGPoint(x: xOffset, y: 0),
						advance: advances[i].width
					)
					glyphs.append(data)
				}
				xOffset += advances[i].width
			}
		}
		return glyphs
	}
}
