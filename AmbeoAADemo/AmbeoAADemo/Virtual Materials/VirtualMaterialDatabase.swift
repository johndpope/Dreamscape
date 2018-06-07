/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// A type which controls the manipulation of virtual materials.

import Foundation
import ARKit

class VirtualMaterialDatabase {

    static let availableMaterials: [VirtualMaterial] = {
        guard let jsonURL = Bundle.main.url(forResource: "VirtualMaterials", withExtension: "json") else {
                fatalError("Missing 'VirtualMaterials.json' in bundle.")
        }

        do {
            let jsonData = try Data(contentsOf: jsonURL)
            return try JSONDecoder().decode([VirtualMaterial].self, from: jsonData)
        } catch {
            fatalError("Unable to decode VirtualMaterials JSON: \(error)")
        }
    }()

}
