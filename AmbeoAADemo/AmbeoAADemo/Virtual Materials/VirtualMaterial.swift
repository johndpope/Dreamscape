/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import Foundation
import SceneKit
import ARKit

struct VirtualMaterial: Codable, Equatable {

    let materialName: String
    let displayName: String
    let fileName: String
    lazy var thumbImage: UIImage = UIImage(named: self.fileName)!

    init(materialName: String, displayName: String, fileName: String) {
        self.materialName = materialName
        self.displayName = displayName
        self.fileName = fileName
    }

    static func ==(lhs: VirtualMaterial, rhs: VirtualMaterial) -> Bool {
        return lhs.materialName == rhs.materialName
            && lhs.displayName == rhs.displayName
            && lhs.fileName == rhs.fileName
    }
}
