/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// Methods on the main view controller for handling LeiaShoeboxEnvironment

import ARKit
import SceneKit
import UIKit

extension ViewController  {

    // IDs for LeiaAU shoebox environment surfaces
    // See `LeiaSurfaceID` in `SennheiserAmbeoLeia.h`
    enum LeiaAuSurfaceId: Int32 {
        case Direct = 0,
        Left,
        Front,
        Right,
        Back,
        Ceiling,
        Floor
    }

    // MARK: - Environment functions

    /**
     * Searches the current frame for "anchorNodeFloor", if it exists, and returns the
     * world coordinate position on the floor corresponding to the given point in the view.
     *
     * @param location A 2D point in the view’s coordinate system. In this demo app, this is typically the center of the screen.
     * @param usingExtent If true, the search will only hit test against the physical extent of the floor. If false, the search will assume an infinite floor.
     * @return A 3D point in the world coordinate system, on the floor, corresponding to the given 2D 'location'.
     */
    private func getWorldPositionAtFloor(location: CGPoint, usingExtent: Bool) -> SCNVector3? {
        let results = sceneView.hitTest(location, types: usingExtent ? ARHitTestResult.ResultType.existingPlaneUsingExtent : ARHitTestResult.ResultType.existingPlane)
        guard results.count > 0 else { return nil }
        for result in results {
            if let anchor = result.anchor {
                if (sceneView.node(for: anchor)?.name == "anchorNodeFloor") {
                    guard anchor is ARPlaneAnchor else { return nil }
                    return SCNVector3Make(result.worldTransform.columns.3.x, result.worldTransform.columns.3.y, result.worldTransform.columns.3.z)
                }
            }
        }
        return nil
    }

    /** Updates uniform height of all LeiaShoeboxEnvironment vertical surfaces (walls) according to user's orientation */
    func updateHeightTracking() {
        let distance = shoeboxOrigin!.distance(vector: (sceneView.pointOfView?.worldPosition)!)
        let trackingNode = SCNNode(geometry: SCNSphere(radius: 0.005))
        trackingNode.position = SCNVector3Make(0.0, 0.0, -1.0 * distance)
        sceneView.pointOfView?.addChildNode(trackingNode)
        var up = shoeboxOrigin!
        up.y += 1
        let directionVector = shoeboxOrigin! - up
        var wallEndPosition = closest3DPointOnLine(pointOff: trackingNode.worldPosition, pointThru: shoeboxOrigin!, direction: directionVector)
        trackingNode.removeFromParentNode()

        wallEndPosition.x = shoeboxOrigin!.x
        wallEndPosition.z = shoeboxOrigin!.z

        self.shoeboxHeight = Float(max(wallEndPosition.y - shoeboxOrigin!.y, 0.01))
        self.updateLeiaShoeboxEnvironment()
    }

    /** Respond to notification when the user changes an environment material */
    @objc func materialChanged(notification: Notification) {
        guard let material = notification.object as? VirtualMaterial else { return }
        guard let node = self.currentlySelectedNode else { return }
        updateEnvironmentMaterial(node: node, material: material)
    }

    /** Update the scene and LeiaAU Shoebox with the selected material */
    private func updateEnvironmentMaterial(node: SCNNode?, material: VirtualMaterial) {
        guard (node != nil) else { return }

        if (material.materialName != "off") {
            node!.geometry?.firstMaterial?.diffuse.contents = UIImage(imageLiteralResourceName: String(material.materialName + ".png"))
        } else {
            node!.geometry?.firstMaterial?.diffuse.contents = ViewController.colorEnvironmentSurface
        }
        if let surface = node!.name {
            self.surfaceMaterials[surface] = material.materialName
        }
        node!.geometry?.firstMaterial?.diffuse.wrapS = SCNWrapMode.repeat
        node!.geometry?.firstMaterial?.diffuse.wrapT = SCNWrapMode.repeat

        var surfaceId: LeiaAuSurfaceId?
        if (node!.name == "LEFT") {
            surfaceId = LeiaAuSurfaceId.Left
        } else if (node!.name == "FRONT") {
            surfaceId = LeiaAuSurfaceId.Front
        } else if (node!.name == "RIGHT") {
            surfaceId = LeiaAuSurfaceId.Right
        } else if (node!.name == "BACK") {
            surfaceId = LeiaAuSurfaceId.Back
        } else if (node!.name == "CEILING") {
            surfaceId = LeiaAuSurfaceId.Ceiling
        } else if (node!.name == "FLOOR") {
            surfaceId = LeiaAuSurfaceId.Floor
        } else {
            return
        }
        if (surfaceId != nil) {
            self.leiaAU.setLeiaAuEnvironmentShoeboxReflectionMaterialForPath(surfaceId!.rawValue, material.materialName)
        }

        node?.geometry?.firstMaterial?.emission.contents = UIColor.black
        print("Painted surface \(node?.name ?? String("nil")) with material \(material.displayName)")
        self.currentlySelectedNode = nil

    }
    
    /** Updates a horizontal or vertical surface node's material for rendering and adds it to the scene */
    func updateEnvironmentSurface(surface: SCNNode, name: String) {
        surface.name = name
        if let materialName = self.surfaceMaterials[name], materialName != "off" {
            surface.geometry?.firstMaterial?.diffuse.contents = UIImage(imageLiteralResourceName: String(materialName + ".png"))
        }
        self.sceneView.scene.rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode()
        self.sceneView.scene.rootNode.addChildNode(surface)
    }

    /** Updates a new vertical surface (wall) for rendering with the given dimensions */
    func updateEnvironmentSurfaceVertical(name: String, start: SCNVector3, end: SCNVector3, height: CGFloat) {
        let surface = Surface.nodeVertical(start: start, end: end, height: height)
        updateEnvironmentSurface(surface: surface, name: name)
    }

    /** Updates a new horizontal surface (floor or ceiling) for rendering with the given dimensions */
    func updateEnvironmentSurfaceHorizontal(name: String, start: SCNVector3, end: SCNVector3, length: CGFloat) {
        let surface = Surface.nodeHorizontal(start: start, end: end, length: length)
        updateEnvironmentSurface(surface: surface, name: name)
    }

    /** Updates a marker for rendering at the given corner of the shoebox environment, in world coordinates */
    func updateCornerMarker(name: String, position: SCNVector3, color: UIColor) {
        let marker = Marker.markerGeneric(position: position, color: color)
        marker.name = name
        self.sceneView.scene.rootNode.childNode(withName: name, recursively: false)?.removeFromParentNode()
        self.sceneView.scene.rootNode.addChildNode(marker)
    }

    /** Removes all shoebox environment surfaces and markers from the scene */
    func hideLeiaShoeboxEnvironment(_ hide: Bool) {
        self.sceneView.scene.rootNode.childNode(withName: "LEFT", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "FRONT", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "RIGHT", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "BACK", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "CEILING", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "FLOOR", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "cornerOrigin", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "cornerWidth", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "cornerLength", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "cornerOpposite", recursively: false)?.isHidden = hide
        self.sceneView.scene.rootNode.childNode(withName: "cornerHeight", recursively: false)?.isHidden = hide
    }

    /** Create a default Shoebox room with default materials */
    func createLeiaShoeboxEnvironment() {

        DispatchQueue.main.async {
            self.leiaAU.setLeiaAuEnvironmentShoebox(10.0, 5.0, 10.0) // reasonable default values
            self.isEnvironmentModeEnabled = true  // temporarily enable environment mode so we can render our default shoebox
            self.updateLeiaShoeboxEnvironment()   // immediately calculate a best-fit shoebox
            print("Default LeiaShoeboxEnvironment created")

            // Assign drapes material (i.e. `heavy_velour`) to the walls by default.
            if let materialDrapes = VirtualMaterialDatabase.availableMaterials.first(where: { $0.materialName == "heavy_velour" }) {
                self.updateEnvironmentMaterial(node: self.sceneView.scene.rootNode.childNode(withName: "LEFT", recursively: false), material: materialDrapes)
                self.updateEnvironmentMaterial(node: self.sceneView.scene.rootNode.childNode(withName: "FRONT", recursively: false), material: materialDrapes)
                self.updateEnvironmentMaterial(node: self.sceneView.scene.rootNode.childNode(withName: "RIGHT", recursively: false), material: materialDrapes)
                self.updateEnvironmentMaterial(node: self.sceneView.scene.rootNode.childNode(withName: "BACK", recursively: false), material: materialDrapes)
            }

            // Assign wood material (i.e. `gypsum_board`) to the ceiling by default
            if let materialWood = VirtualMaterialDatabase.availableMaterials.first(where: { $0.materialName == "heavy_velour" }) {
                self.updateEnvironmentMaterial(node: self.sceneView.scene.rootNode.childNode(withName: "CEILING", recursively: false), material: materialWood)
            }

            // Assign carpet material (i.e. `carpet_heavy`) to the floor by default
            if let materialCarpet = VirtualMaterialDatabase.availableMaterials.first(where: { $0.materialName == "carpet_heavy" }) {
                self.updateEnvironmentMaterial(node: self.sceneView.scene.rootNode.childNode(withName: "FLOOR", recursively: false), material: materialCarpet)
            }

            self.isEnvironmentModeEnabled = false // disable environment mode, now that we have rendered the default shoebox
            self.hideLeiaShoeboxEnvironment(true) // hide the newly-rendered default shoebox until a user explicitly shows it
        }
    }

    /** Calculates a best-fit shoebox environment around the tracked floorPlaneNode */
    func updateLeiaShoeboxEnvironment() {
        if (self.currentUIState == UIState.uiPlay) { return }
        guard (!self.isEnvironmentLocked) else { return }
        guard let planeNode = self.floorPlaneNode else { return }
        let min = planeNode.boundingBox.min
        let max = planeNode.boundingBox.max

        // LeiaShoebox +Y corner (length)
        let cornerLength = planeNode.convertPosition(min, to: self.sceneView.scene.rootNode)

        // LeiaShoebox +X corner (width)
        let cornerWidth = planeNode.convertPosition(max, to: self.sceneView.scene.rootNode)

        // LeiaShoebox origin
        let cornerOrigin = planeNode.convertPosition(SCNVector3Make(min.x, min.y, max.z), to: self.sceneView.scene.rootNode)

        // LeiaShoebox opposite corner
        let cornerOpposite = planeNode.convertPosition(SCNVector3Make(max.x, min.y, min.z), to: self.sceneView.scene.rootNode)

        // LeiaShoebox +Z corner (height)
        let height = self.shoeboxHeight // default height of 3 meters
        let cornerHeight = planeNode.convertPosition(SCNVector3Make(min.x, min.y + height, max.z), to: self.sceneView.scene.rootNode)

        let width =  cornerOrigin.distance(vector: cornerWidth)
        let length = cornerOrigin.distance(vector: cornerLength)

        // render surfaces and corner markers
        if (self.isEnvironmentModeEnabled) { // if in "environment mode"

            self.updateEnvironmentSurfaceVertical(name: "LEFT", start: cornerOrigin, end: cornerLength, height: CGFloat(height))
            self.updateEnvironmentSurfaceVertical(name: "FRONT", start: cornerOpposite, end: cornerLength, height: CGFloat(height))
            self.updateEnvironmentSurfaceVertical(name: "RIGHT", start: cornerWidth, end: cornerOpposite, height: CGFloat(height))
            self.updateEnvironmentSurfaceVertical(name: "BACK", start: cornerOrigin, end: cornerWidth, height: CGFloat(height))

            var midpointWidth =  cornerWidth.midpoint(vector: cornerOpposite)
            var midpointLength = cornerLength.midpoint(vector: cornerOrigin)
            self.updateEnvironmentSurfaceHorizontal(name: "FLOOR", start: midpointLength, end: midpointWidth, length: CGFloat(length))
            midpointWidth.y = cornerHeight.y
            midpointLength.y = cornerHeight.y
            self.updateEnvironmentSurfaceHorizontal(name: "CEILING", start: midpointLength, end: midpointWidth, length: CGFloat(length))

            self.updateCornerMarker(name: "cornerOrigin", position: cornerOrigin, color: UIColor.white)
            self.updateCornerMarker(name: "cornerWidth", position: cornerWidth, color: UIColor.red)
            self.updateCornerMarker(name: "cornerLength", position: cornerLength, color: UIColor.blue)
            self.updateCornerMarker(name: "cornerOpposite", position: cornerOpposite, color: UIColor.black)
            self.updateCornerMarker(name: "cornerHeight", position: cornerHeight, color: UIColor.green)
        }

        // update shoebox
        self.shoeboxOrigin = cornerOrigin
        self.shoeboxDimensions = (width, length, height)

        let directionVectorLeiaX = simd_float3.init((cornerWidth - self.shoeboxOrigin!).normalize())
        let angle = atan2(directionVectorLeiaX.z, directionVectorLeiaX.x) // * -1 ?
        self.leiaAU.setLeiaAuEnvironmentShoeboxOrientationEuler(angle, 0.0, 0.0)

        self.leiaAU.setLeiaAuEnvironmentShoeboxOrigin(self.shoeboxOrigin!.x, self.shoeboxOrigin!.y, self.shoeboxOrigin!.z)

        self.leiaAU.setLeiaAuEnvironmentShoeboxDimensions(width, length, height)

        DispatchQueue.main.async {
            self.ambeoEngine.updateAllObjectPositions() // update Leia object positions to new internal coordinate system
        }
    }
    
}
