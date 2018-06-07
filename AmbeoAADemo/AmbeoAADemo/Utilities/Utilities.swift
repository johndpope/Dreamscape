/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// Utility functions and type extensions used throughout the projects.

import Foundation
import ARKit

// MARK: - Collection extensions
extension Array where Iterator.Element == Float {
    var average: Float? {
        guard !self.isEmpty else {
            return nil
        }

        let sum = self.reduce(Float(0)) { current, next in
            return current + next
        }
        return sum / Float(self.count)
    }
}

extension Array where Iterator.Element == float3 {
    var average: float3? {
        guard !self.isEmpty else {
            return nil
        }

        let sum = self.reduce(float3(0)) { current, next in
            return current + next
        }
        return sum / Float(self.count)
    }
}

extension RangeReplaceableCollection {
    mutating func keepLast(_ elementsToKeep: Int) {
        if count > elementsToKeep {
            self.removeFirst(count - elementsToKeep)
        }
    }
}

// MARK: - SCNNode extension

extension SCNNode {

    func setUniformScale(_ scale: Float) {
        self.simdScale = float3(scale, scale, scale)
    }

    func renderOnTop(_ enable: Bool) {
        self.renderingOrder = enable ? 2 : 0
        if let geom = self.geometry {
            for material in geom.materials {
                material.readsFromDepthBuffer = enable ? false : true
            }
        }
        for child in self.childNodes {
            child.renderOnTop(enable)
        }
    }

    func findNode(name: String) -> SCNNode? {
        print("visited node \(self.name ?? String("NO NAME"))")
        if (self.name == name) {
            return self
        } else {
            for child in self.childNodes {
                return child.findNode(name: name)
            }
        }
        return nil
    }
    
    func printAllDescendantNames() {
        print(self.name ?? "no_name")
        self.childNodes.forEach { $0.printAllDescendantNames() }
    }
    
}

// MARK: - float4x4 extensions

extension float4x4 {
    /**
     Treats matrix as a (right-hand column-major convention) transform matrix
     and factors out the translation component of the transform.
     */
    var translation: float3 {
        get {
            let translation = columns.3
            return float3(translation.x, translation.y, translation.z)
        }
        set(newValue) {
            columns.3 = float4(newValue.x, newValue.y, newValue.z, columns.3.w)
        }
    }

    /**
     Factors out the orientation component of the transform.
     */
    var orientation: simd_quatf {
        return simd_quaternion(self)
    }

    /**
     Creates a transform matrix with a uniform scale factor in all directions.
     */
    init(uniformScale scale: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scale
        columns.1.y = scale
        columns.2.z = scale
    }
}

// MARK: - CGPoint extensions

extension CGPoint {

    init(_ size: CGSize) {
        self.init(x: CGFloat(size.width), y: CGFloat(size.height))
    }

    /// Extracts the screen space point from a vector returned by SCNView.projectPoint(_:).
    init(_ vector: SCNVector3) {
        self.init(x: CGFloat(vector.x), y: CGFloat(vector.y))
    }

    func distanceTo(_ point: CGPoint) -> CGFloat {
        return (self - point).length()
    }

    /// Returns the length of a point when considered as a vector. (Used with gesture recognizers.)
    func length() -> CGFloat {
        return sqrt(self.x * self.x + self.y * self.y)
    }

    func midpoint(_ point: CGPoint) -> CGPoint {
        return (self + point) / 2
    }

    func dot(vector: CGPoint) -> CGFloat {
        return self.x*vector.x + self.y*vector.y
    }

    static func normalized(point: CGPoint) -> CGPoint {
        let length = point.length()
        return CGPoint(x: point.x/length, y: point.y/length)
    }

    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x + right.x, y: left.y + right.y)
    }

    static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x - right.x, y: left.y - right.y)
    }

    static func += (left: inout CGPoint, right: CGPoint) {
        left = left + right
    }

    static func -= (left: inout CGPoint, right: CGPoint) {
        left = left - right
    }

    static func / (left: CGPoint, right: CGFloat) -> CGPoint {
        return CGPoint(x: left.x / right, y: left.y / right)
    }

    static func * (left: CGPoint, right: CGFloat) -> CGPoint {
        return CGPoint(x: left.x * right, y: left.y * right)
    }

    static func /= (left: inout CGPoint, right: CGFloat) {
        left = left / right
    }

    static func *= (left: inout CGPoint, right: CGFloat) {
        left = left * right
    }

}

// MARK: - CGSize extensions

extension CGSize {
    init(_ point: CGPoint) {
        self.init()
        self.width = point.x
        self.height = point.y
    }

    static func + (left: CGSize, right: CGSize) -> CGSize {
        return CGSize(width: left.width + right.width, height: left.height + right.height)
    }

    static func - (left: CGSize, right: CGSize) -> CGSize {
        return CGSize(width: left.width - right.width, height: left.height - right.height)
    }

    static func += (left: inout CGSize, right: CGSize) {
        left = left + right
    }

    static func -= (left: inout CGSize, right: CGSize) {
        left = left - right
    }

    static func / (left: CGSize, right: CGFloat) -> CGSize {
        return CGSize(width: left.width / right, height: left.height / right)
    }

    static func * (left: CGSize, right: CGFloat) -> CGSize {
        return CGSize(width: left.width * right, height: left.height * right)
    }

    static func /= (left: inout CGSize, right: CGFloat) {
        left = left / right
    }

    static func *= (left: inout CGSize, right: CGFloat) {
        left = left * right
    }
}

// MARK: - CGRect extensions

extension CGRect {
    var mid: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}

func rayIntersectionWithHorizontalPlane(rayOrigin: float3, direction: float3, planeY: Float) -> float3? {

    let direction = simd_normalize(direction)

    // Special case handling: Check if the ray is horizontal as well.
    if direction.y == 0 {
        if rayOrigin.y == planeY {
            // The ray is horizontal and on the plane, thus all points on the ray intersect with the plane.
            // Therefore we simply return the ray origin.
            return rayOrigin
        } else {
            // The ray is parallel to the plane and never intersects.
            return nil
        }
    }

    // The distance from the ray's origin to the intersection point on the plane is:
    //   (pointOnPlane - rayOrigin) dot planeNormal
    //  --------------------------------------------
    //          direction dot planeNormal

    // Since we know that horizontal planes have normal (0, 1, 0), we can simplify this to:
    let dist = (planeY - rayOrigin.y) / direction.y

    // Do not return intersections behind the ray's origin.
    if dist < 0 {
        return nil
    }

    // Return the intersection point.
    return rayOrigin + (direction * dist)
}

// MARK: - SCNVector3 extensions

extension SCNVector3 {

    static func +(left:SCNVector3, right:SCNVector3) -> SCNVector3 {
        return SCNVector3(left.x + right.x, left.y + right.y, left.z + right.z)
    }

    static func -(left:SCNVector3, right:SCNVector3) -> SCNVector3 {
        return left + (right * -1.0)
    }

    static func *(vector:SCNVector3, multiplier:SCNFloat) -> SCNVector3 {
        return SCNVector3(vector.x * multiplier, vector.y * multiplier, vector.z * multiplier)
    }

    func length() -> Float {
        return sqrtf(self.x*self.x + self.y*self.y + self.z*self.z)
    }

    func normalize() -> SCNVector3 {
        let length = self.length()
        return SCNVector3(self.x/length, self.y/length, self.z/length)
    }

    func distance(vector: SCNVector3) -> Float {
        return (self - vector).length()
    }

    func dot(vector: SCNVector3) -> Float {
        return self.x*vector.x + self.y*vector.y + self.z*vector.z
    }

    func midpoint(vector: SCNVector3) -> SCNVector3 {
        return SCNVector3( (self.x+vector.x)/2.0, (self.y+vector.y)/2.0, (self.z+vector.z)/2.0)
    }

    func negate() -> SCNVector3 {
        return self * -1
    }

}

public func GLKMatrix4MakeWith_matrix_float4x4(_ m: matrix_float4x4) -> GLKMatrix4 {
    return GLKMatrix4Make(m[0][0], m[0][1], m[0][2], m[0][3], m[1][0], m[1][1], m[1][2], m[1][3], m[2][0], m[2][1], m[2][2], m[2][3], m[3][0], m[3][1], m[3][2], m[3][3])
}

/* pointOff  - the original point, not on the line
 * pointThru - a point the line passes through
 * direction - direction of the line (sign does not matter)
 */
public func closest3DPointOnLine(pointOff: SCNVector3, pointThru: SCNVector3, direction: SCNVector3) -> SCNVector3 {
    let directionNorm = direction.normalize() //this needs to be a unit vector
    let v = pointOff - pointThru
    let d = v.dot(vector: directionNorm)
    return pointThru + directionNorm * d
}

/* pointOff  - the original point, not on the line
 * pointThru - a point the line passes through
 * direction - direction of the line (sign does not matter)
 */
public func closest2DPointOnLine(pointOff: CGPoint, pointThru: CGPoint, direction: CGPoint) -> CGPoint {
    let directionNorm = CGPoint.normalized(point: direction) //this needs to be a unit vector
    let v = pointOff - pointThru
    let d = v.dot(vector: directionNorm)
    return pointThru + directionNorm * d
}
