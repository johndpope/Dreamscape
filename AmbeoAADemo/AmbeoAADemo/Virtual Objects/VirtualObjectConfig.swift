/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import UIKit
import Foundation

struct VirtualObjectConfig: Codable, Equatable {

    lazy var thumbImage: UIImage = UIImage(named: self.modelName)!
    var modelName: String
    var displayName: String

    var allowedAlignments: [String]

    var audioFile: [String]

    init(modelName: String, displayName: String, audioFile: [String], allowedAlignments: [String]) {
        self.modelName = modelName
        self.displayName = displayName
        self.audioFile = audioFile
        self.allowedAlignments = allowedAlignments
    }

    static func ==(lhs: VirtualObjectConfig, rhs: VirtualObjectConfig) -> Bool {
        return lhs.modelName == rhs.modelName
    }
}
