/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import Foundation
import SceneKit

class Surface {

    class func surfaceMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = ViewController.colorEnvironmentSurface
        material.lightingModel = SCNMaterial.LightingModel.physicallyBased
        material.isDoubleSided = true
        return material
    }

    class func nodeVertical(start: SCNVector3, end: SCNVector3, height: CGFloat) -> SCNNode {
        let distance = start.distance(vector: end)
        let surface = SCNPlane(width: CGFloat(distance), height: height)
        surface.firstMaterial = surfaceMaterial()
        let node = SCNNode(geometry: surface)
        node.opacity = 0.3
        node.renderingOrder = -10

        // center point
        node.position = SCNVector3(start.x + (end.x - start.x) * 0.5, start.y + Float(height) * 0.5, start.z + (end.z - start.z) * 0.5)

        // NOTE: this does not consider the poistion of the camera. Moving right of the initial
        // orientation will orient the surface away from the camera, and if the surface's geometry's
        // material 'isDoubleSided' == false, then it will not be rendered.
        node.eulerAngles = SCNVector3(0, -atan2(end.x - node.position.x, start.z - node.position.z) - Float.pi * 0.5, 0)

        node.name = "surface"
        return node
    }

    class func nodeHorizontal(start: SCNVector3, end: SCNVector3, length: CGFloat) -> SCNNode {
        let distance = start.distance(vector: end)
        let surface = SCNPlane(width: CGFloat(distance), height: length)
        surface.firstMaterial = surfaceMaterial()
        let node = SCNNode(geometry: surface)
        node.opacity = 0.3
        node.renderingOrder = -10

        // center point
        node.position = SCNVector3(start.x + (end.x - start.x) * 0.5, start.y, start.z + (end.z - start.z) * 0.5)

        // NOTE: this does not consider the poistion of the camera. Moving right of the initial
        // orientation will orient the surface away from the camera, and if the surface's geometry's
        // material 'isDoubleSided' == false, then it will not be rendered.
        node.eulerAngles = SCNVector3(Float.pi/2.0, -atan2(end.x - node.position.x, start.z - node.position.z) - Float.pi * 0.5, 0)

        node.name = "surface"
        return node
    }
    
}

