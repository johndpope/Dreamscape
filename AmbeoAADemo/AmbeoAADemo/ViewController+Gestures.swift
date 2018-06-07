/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// Coordinates movement and gesture interactions with virtual objects.

import UIKit
import ARKit

extension ViewController: UIGestureRecognizerDelegate {

    /**
     * Add gesture recognizers for pan, rotation, and tap.
     */
    func setupGestures() {

        let panGesture = ThresholdPanGesture(target: self, action: #selector(didPan(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(didRotate(_:)))
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(_:)))
        sceneView.addGestureRecognizer(panGesture)
        sceneView.addGestureRecognizer(rotationGesture)
        sceneView.addGestureRecognizer(tapGesture)
    }

    // MARK: - Gesture Actions

    /**
     * Handles the panning (or dragging) of a user's finger on the device. This updates object positions.
     */
    @objc func didPan(_ gesture: ThresholdPanGesture) {
        switch gesture.state {
        case .began:
            // Check for interaction with a new object.
            if let object = objectInteracting(with: gesture, in: sceneView) {
                trackedObject = object
            }

        case .changed where gesture.isThresholdExceeded:
            guard let object = trackedObject else { return }
            translate(object, basedOn: gesture.location(in: sceneView), infinitePlane: false, allowAnimation: false)

            // update corresponding LeiaSource position
            self.leiaAU.setLeiaAuSourcePosition(object.leiaAUSourceID!, object.worldPosition.x, object.worldPosition.y, object.worldPosition.z)

        case .changed:
            // Ignore changes to the pan gesture until the threshold for displacment has been exceeded.
            break

        case .ended:
            // Update the object's anchor when the gesture ended.
            guard let existingTrackedObject = trackedObject else { break }
            sceneView.addOrUpdateAnchor(for: existingTrackedObject)
            fallthrough

        default:
            // Clear the current position tracking.
            currentTrackingPosition = nil
            trackedObject = nil
        }
    }

    /**
     * If a drag gesture is in progress, update the tracked object's position by
     * converting the 2D touch location on screen (`currentTrackingPosition`) to
     * 3D world space.
     * This method is called per frame (via `SCNSceneRendererDelegate` callbacks),
     * allowing drag gestures to move virtual objects regardless of whether one
     * drags a finger across the screen or moves the device through space.
     */
    @objc func updateObjectToCurrentTrackingPosition() {
        guard let object = trackedObject, let position = currentTrackingPosition else { return }
        translate(object, basedOn: position, infinitePlane: translateAssumingInfinitePlane, allowAnimation: true)
    }

    /**
     * Handles the rotation of a user's two fingers on the device. This updates object orientations.
     */
    @objc func didRotate(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Check for interaction with a new object.
            if let object = objectInteracting(with: gesture, in: sceneView) {
                trackedObject = object
            }
        case .changed:
            trackedObject?.objectRotation -= Float(gesture.rotation)
            gesture.rotation = 0
        case .ended:
            fallthrough
        default:
            // Clear the current position tracking.
            currentTrackingPosition = nil
            trackedObject = nil
        }
        guard gesture.state == .changed else { return }
    }

    /**
     * Handles the tapping of a user's finger on the device. This segues to the available
     * VirtualMaterials view controller when in the painting materials UIState.
     */
    @objc func didTap(_ gesture: UITapGestureRecognizer) {
        let touchLocation = gesture.location(in: sceneView)
        if sceneView.findObject(at: touchLocation) != nil {
            // User tapped object
        } else if (currentUIState == UIState.uiPaintMaterial) {
            if let surface = identifyVirtualPlane(at: touchLocation, sceneView: sceneView) {
                // User tapped surface
                if let surfaceName = surface.name, (self.surfaceMaterials[surfaceName] != nil) {
                    updateCurrentlySelectedNode(surface)
                    performSegue(withIdentifier: SegueIdentifier.showMaterials.rawValue, sender: self.environmentButton)
                }
            } else {
                // User tapped nothing
            }
        }
    }

    /** Prevents objects from being translated and rotated at the same time. */
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    /**
     * A helper method to return the first object that is found under the provided `gesture`s touch locations.
     */
    private func objectInteracting(with gesture: UIGestureRecognizer, in view: ARSCNView) -> VirtualObject? {
        for index in 0..<gesture.numberOfTouches {
            let touchLocation = gesture.location(ofTouch: index, in: view)

            // Look for an object directly under the `touchLocation`.
            if let object = sceneView.findObject(at: touchLocation) {
                return object
            }
        }

        // As a last resort look for an object under the center of the touches.
        return sceneView.findObject(at: gesture.center(in: view))
    }

    // MARK: - Update object position

    /** Apply translation to VirtualObject. */
    private func translate(_ object: VirtualObject, basedOn screenPos: CGPoint, infinitePlane: Bool, allowAnimation: Bool) {
        guard let cameraTransform = sceneView.session.currentFrame?.camera.transform,
            let result = sceneView.smartHitTest(screenPos,
                                                infinitePlane: infinitePlane,
                                                objectPosition: object.simdWorldPosition,
                                                allowedAlignments: object.allowedAlignments) else { return }

        let planeAlignment: ARPlaneAnchor.Alignment
        if let planeAnchor = result.anchor as? ARPlaneAnchor {
            planeAlignment = planeAnchor.alignment
        } else if result.type == .estimatedHorizontalPlane {
            planeAlignment = .horizontal
        } else if result.type == .estimatedVerticalPlane {
            planeAlignment = .vertical
        } else {
            return
        }

        // Plane hit test results are generally smooth. If we did not hit a plane,
        // smooth the movement to prevent large jumps.
        let transform = result.worldTransform
        let isOnPlane = result.anchor is ARPlaneAnchor
        object.setTransform(transform,
                            relativeTo: cameraTransform,
                            smoothMovement: !isOnPlane,
                            alignment: planeAlignment,
                            allowAnimation: allowAnimation)
    }

    /** Updates the `currentlySelectedNode`. */
    func updateCurrentlySelectedNode(_ node: SCNNode) {
        self.currentlySelectedNode?.geometry?.firstMaterial?.emission.contents = UIColor.black
        node.geometry?.firstMaterial?.emission.contents = UIColor.white
        self.currentlySelectedNode = node
    }

}

/** Extends `UIGestureRecognizer` to provide the center point resulting from multiple touches. */
extension UIGestureRecognizer {

    func center(in view: UIView) -> CGPoint {
        let first = CGRect(origin: location(ofTouch: 0, in: view), size: .zero)
        let touchBounds = (1..<numberOfTouches).reduce(first) { touchBounds, index in
            return touchBounds.union(CGRect(origin: location(ofTouch: index, in: view), size: .zero))
        }
        return CGPoint(x: touchBounds.midX, y: touchBounds.midY)
    }

}

