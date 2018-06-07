/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// ARSessionDelegate interactions for the main view controller.
// ARSCNViewDelegate interactions for the main view controller.

import ARKit

extension ViewController: ARSessionDelegate, ARSCNViewDelegate {

    // MARK: - ARSessionDelegate

    /** Changed ARCamera tracking state */
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        textManager.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        switch camera.trackingState {
        case .notAvailable, .limited:
            textManager.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            textManager.cancelScheduledMessage(forType: .trackingStateEscalation)
            // Unhide content after successful relocalization.
            virtualObjectLoader.loadedObjects.forEach { $0.isHidden = false }
        }
    }

    /** ARSession failed with error */
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        // Use `flatMap(_:)` to remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }

    /** ARSession was interrupted */
    func sessionWasInterrupted(_ session: ARSession) {
        // Hide content before going into the background.
        virtualObjectLoader.loadedObjects.forEach { $0.isHidden = true }
        textManager.blurBackground()
        textManager.showAlert(title: "Session Interrupted", message: "The session will be reset after the interruption has ended.")
    }

    /** ARSession interruption ended */
    func sessionInterruptionEnded(_ session: ARSession) {
        textManager.unblurBackground()
        touchRestartButton(self)
        displayGlobalMessage("Session reset.")
    }

    /**
     * ARSession should attempt to resume after an interruption.
     * This process may not succeed, so the app must be prepared
     * to reset the session if the relocalizing status continues
     * for a long time -- see `escalateFeedback` in `StatusViewController`.
     */
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }

    // MARK: - ARSCNViewDelegate

    /**
     * Called once per frame. Tells the delegate to perform any updates
     * that need to occur before actions, animations, and physics are evaluated.
     * This includes updating LeiaAU listener position and orientation.
     */
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {

        DispatchQueue.main.async {

            // Get 4x4 transform matrix of ARCamera in world coordinate space
            guard let cameraTransform = self.session.currentFrame?.camera.transform else { return }

            // Update LeiaAU listener position coordinates from transform
            let x: Float = cameraTransform.columns.3.x
            let y: Float = cameraTransform.columns.3.y
            let z: Float = cameraTransform.columns.3.z
            self.leiaAU.setLeiaAuListenerPosition(x, y, z)

            // You can update the LeiaAU listener orientation with the Euler
            // angles of the ARCamera.
            guard let cameraEuler = self.session.currentFrame?.camera.eulerAngles else { return }
            let pitch = cameraEuler.x
            let yaw   = cameraEuler.y
            let roll  = cameraEuler.z
            self.leiaAU.setLeiaAuListenerOrientationEuler(yaw, pitch, roll)

            // Alternatively you can also set the orientation from a quaternion.
            // let q = GLKQuaternionMakeWithMatrix4(GLKMatrix4MakeWith_matrix_float4x4(cameraTransform))
            // self.leiaAU.setLeiaAuListenerOrientationQuaternion(q.w, q.x, q.y, q.z)

            if (self.currentUIState == UIState.uiMeasureEnvironmentHeight) {
                self.updateHeightTracking()
            }
            self.updateFocusSquare()
        }

        // If the object selection menu is open, update availability of items
        if objectsViewController != nil {
            let planeAnchor = focusSquare.currentPlaneAnchor
            objectsViewController?.updateObjectAvailability(for: planeAnchor)
        }

        // If light estimation is enabled, update the intensity of the model's lights and the environment map
        let baseIntensity: CGFloat = 40
        let lightingEnvironment = sceneView.scene.lightingEnvironment
        if let lightEstimate = session.currentFrame?.lightEstimate {
            lightingEnvironment.intensity = lightEstimate.ambientIntensity / baseIntensity
        } else {
            lightingEnvironment.intensity = baseIntensity
        }

    }

    /** Added an SCNNode */
    func renderer(_ renderer: SCNSceneRenderer, didAdd addedNode: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        DispatchQueue.main.async {
            self.textManager.cancelScheduledMessage(forType: .planeEstimation)
            self.displayGlobalMessage("New surface detected.")
        }
        let planeNode = self.createPlaneNode(planeAnchor: planeAnchor)
        updateQueue.async {
            addedNode.addChildNode(planeNode)
            if (self.session.currentFrame?.anchors.count == 1 || addedNode.worldPosition.y < self.getFloorY()) {
                if (self.session.currentFrame?.anchors.count == 1) {
                    // we found our first floor, so create a default
                    // LeiaShoeboxEnvironment, which will be updated in self.updateFloor
                    self.createLeiaShoeboxEnvironment()
                } else if (self.session.currentFrame?.anchors.count != 1) {
                    // we found a new floor, assign it the "floor"
                    // name and remove that name from the old floor
                    self.swapFloorName(newFloorNode: addedNode)
                }
                addedNode.name = "anchorNodeFloor"
                self.updateFloor(anchorNode: addedNode, planeNode: planeNode)
                DispatchQueue.main.async {
                    self.displayGlobalMessage("New surface identified as floor.")
                }
            }
            for object in self.virtualObjectLoader.loadedObjects {
                object.adjustOntoPlaneAnchor(planeAnchor, using: addedNode)
            }
        }
    }

    /** Updated an SCNNode */
    func renderer(_ renderer: SCNSceneRenderer, didUpdate updatedNode: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else {
            updateQueue.async {
                if let objectAtAnchor = self.virtualObjectLoader.loadedObjects.first(where: { $0.anchor == anchor }) {
                    objectAtAnchor.simdPosition = anchor.transform.translation
                    objectAtAnchor.anchor = anchor
                }
            }
            return
        }
        let planeNode = self.createPlaneNode(planeAnchor: planeAnchor)
        updateQueue.async {
            updatedNode.enumerateChildNodes { (childNode, _) in
                childNode.removeFromParentNode()
            }
            updatedNode.addChildNode(planeNode)
            if (updatedNode.worldPosition.y < self.getFloorY() || updatedNode.name == "anchorNodeFloor") {
                self.updateFloor(anchorNode: updatedNode, planeNode: planeNode)
                if (updatedNode.name != "anchorNodeFloor") {
                    // we found a new floor, so assign it the "floor"
                    // name and remove that name from the old floor
                    self.swapFloorName(newFloorNode: updatedNode)
                    updatedNode.name = "anchorNodeFloor"
                }
            }
            for object in self.virtualObjectLoader.loadedObjects {
                object.adjustOntoPlaneAnchor(planeAnchor, using: updatedNode)
            }
        }
    }

    /** Removed an SCNNode */
    func renderer(_ renderer: SCNSceneRenderer, didRemove removedNode: SCNNode, for anchor: ARAnchor) {
        guard let _ = anchor as? ARPlaneAnchor else { return }
        DispatchQueue.main.async {
            self.displayGlobalMessage("Surface removed/merged.")
        }
        updateQueue.async {
            removedNode.enumerateChildNodes { (childNode, _) in
                childNode.removeFromParentNode()
            }
            if (removedNode.name == "anchorNodeFloor") { // we merged the anchorNodeFloor and removed it, so we must identify which anchorNode is the new floor
                var minY = Float(0.0)
                var replacementNode = SCNNode()
                for anchor in (self.session.currentFrame?.anchors)! {
                    if let node = self.sceneView.node(for: anchor) {
                        if (node.worldPosition.y < minY) {
                            minY = node.worldPosition.y
                            replacementNode = node
                        }
                    }
                }
                guard let planeNode = replacementNode.childNode(withName: "planeNode", recursively: false) else { return }
                self.updateFloor(anchorNode: replacementNode, planeNode: planeNode)
                replacementNode.name = "anchorNodeFloor"
            }
        }
    }

    /** Create a visual representation of the given ARPlaneAnchor */
    func createPlaneNode(planeAnchor: ARPlaneAnchor) -> SCNNode {
        guard let scenePlaneGeometry = ARSCNPlaneGeometry(device: MTLCreateSystemDefaultDevice()!) else {
            return SCNNode(geometry: nil)
        }
        scenePlaneGeometry.update(from: planeAnchor.geometry)
        let planeNode = SCNNode(geometry: scenePlaneGeometry)
        if (isDebugModeEnabled) {
            planeNode.opacity = 0.25
            planeNode.geometry?.firstMaterial?.colorBufferWriteMask = [SCNColorMask.all] // do not occlude, show plane
            planeNode.renderingOrder = 0
        } else {
            planeNode.geometry?.firstMaterial?.colorBufferWriteMask = [] // occlude, hide plane
            planeNode.renderingOrder = -1
        }
        if planeAnchor.alignment == .horizontal {
            planeNode.geometry?.firstMaterial?.diffuse.contents = ViewController.colorPlaneHorizontal
        } else {
            planeNode.geometry?.firstMaterial?.diffuse.contents = ViewController.colorPlaneVertical
        }
        planeNode.name = "planeNode"
        return planeNode
    }

    /**
     * Remove the "anchorNodeFloor" name from the old
     * floor node, and give it to the new floor node
     */
    func swapFloorName(newFloorNode: SCNNode) {
        for findAnchor in (self.session.currentFrame?.anchors)! {
            if let oldFloorNode = self.sceneView.node(for: findAnchor) {
                if oldFloorNode.name == "anchorNodeFloor" {
                    newFloorNode.name = oldFloorNode.name
                    oldFloorNode.name = nil
                    return
                }
            }
        }
    }

    /** Establish the given planeNode as the floor */
    func updateFloor(anchorNode: SCNNode, planeNode: SCNNode) {
        if (isEnvironmentModeEnabled) {
            planeNode.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        } else {
            planeNode.geometry?.firstMaterial?.diffuse.contents = ViewController.colorPlaneFloor
        }
        for anchor in (self.session.currentFrame?.anchors)! {
            let oldFloorNode = self.sceneView.node(for: anchor)
            if oldFloorNode?.name != "anchorNodeFloor" {
                let childNode = oldFloorNode?.childNode(withName: "planeNode", recursively: false)
                childNode?.geometry?.firstMaterial?.diffuse.contents = ViewController.colorPlaneHorizontal
            }
        }
        self.floorPlaneNode = planeNode
        self.updateLeiaShoeboxEnvironment()
    }

    /** Return Y world position of the floor */
    func getFloorY() -> Float {
        guard let y = self.floorPlaneNode?.worldPosition.y else {
            return Float.infinity
        }
        return y
    }

}
