/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import Foundation
import SceneKit

class Marker {

    class func markerGeneric(position:SCNVector3, color: UIColor) -> SCNNode {
        let node = self.markerSphere(color: color)
        node.position = position
        return node
    }

    class private func markerSphere(color: UIColor) -> SCNNode {
        let originStake = SCNSphere(radius: 0.005)
        originStake.firstMaterial?.diffuse.contents = color
        originStake.firstMaterial?.lightingModel = SCNMaterial.LightingModel.physicallyBased
        return SCNNode(geometry: originStake)
    }

    class private func markerStake(color: UIColor) -> SCNNode {
        let originStake = SCNCone(topRadius: 0.005, bottomRadius: 0.0, height: 0.04)
        originStake.firstMaterial?.diffuse.contents = color
        originStake.firstMaterial?.lightingModel = SCNMaterial.LightingModel.physicallyBased
        return SCNNode(geometry: originStake)
    }

}

