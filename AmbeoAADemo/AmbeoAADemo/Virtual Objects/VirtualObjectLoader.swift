/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import Foundation
import ARKit

/**
 * Loads multiple `VirtualObject`s on a background queue to be able to display the
 * objects quickly once they are needed.
 */
class VirtualObjectLoader {
    private(set) var loadedObjects = [VirtualObject]()

    /** Loads all the model objects within `Models.scnassets`. */
    static let availableObjects: [VirtualObject] = {
        guard let jsonURL = Bundle.main.url(forResource: "VirtualObjects", withExtension: "json") else {
            fatalError("Missing 'VirtualObjects.json' in bundle.")
        }

        var foundObjects: [VirtualObject] = []

        do {
            let data = try Data(contentsOf: jsonURL)
            let jsonObjectConfigs = try JSONDecoder().decode([VirtualObjectConfig].self, from: data)
            for objectConfig in jsonObjectConfigs {
                foundObjects.append(VirtualObject(config: objectConfig))
            }
        } catch {
            fatalError("Unable to decode VirtualObjects JSON: \(error)")
        }
        print("Loaded objects from 'VirtualObjects.json'")
        return foundObjects
    }()

    private(set) var isLoading = false

    // MARK: - Loading object

    /**
     * Loads a `VirtualObject` on a background queue. `loadedHandler` is invoked
     * on a background queue once `object` has been loaded.
     */
    func loadVirtualObject(_ object: VirtualObject, loadedHandler: @escaping (VirtualObject) -> Void) {
        isLoading = true
        loadedObjects.append(object)

        // Load the content asynchronously.
        DispatchQueue.global(qos: .userInitiated).async {
            object.reset()
            object.load()

            self.isLoading = false
            loadedHandler(object)
        }
    }

    // MARK: - Removing Objects

    /**
     * Remove all VirtualObjects from the array of currently loaded objects.
     */
    func removeAllVirtualObjects() {
        for object in loadedObjects {
            remove(virtualObject: object)
        }
    }

    /**
     * Remove the given VirtualObject from the array of currently loaded objects.
     */
    func remove(virtualObject: VirtualObject) {
        guard let objectIndex = loadedObjects.index(of: virtualObject) else {
            fatalError("Programmer error: Failed to lookup virtual object in scene.")
        }

        loadedObjects[objectIndex].removeFromParentNode()
        loadedObjects.remove(at: objectIndex)
    }
}
