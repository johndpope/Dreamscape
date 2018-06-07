/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import UIKit
import ARKit

extension ViewController: VirtualObjectSelectionViewControllerDelegate {

    /**
     * Adds the specified virtual object to the scene, placed using
     * the focus square's estimate of the world-space position
     * currently corresponding to the center of the screen.
     */
    func placeVirtualObject(_ virtualObject: VirtualObject) {
        guard let cameraTransform = session.currentFrame?.camera.transform,
            let focusSquareAlignment = focusSquare.recentFocusSquareAlignments.last,
            focusSquare.state != .initializing else {
                textManager.showMessage("CANNOT PLACE OBJECT\nTry moving left or right.")
                if let controller = objectsViewController {
                    virtualObjectSelectionViewController(controller, didDeselectObject: virtualObject)
                }
                return
        }

        // The focus square transform may contain a scale component, so reset scale to 1
        let focusSquareScaleInverse = 1.0 / focusSquare.simdScale.x
        let scaleMatrix = float4x4(uniformScale: focusSquareScaleInverse)
        let focusSquareTransformWithoutScale = focusSquare.simdWorldTransform * scaleMatrix

        selectedObject = virtualObject
        virtualObject.setTransform(focusSquareTransformWithoutScale,
                                   relativeTo: cameraTransform,
                                   smoothMovement: false,
                                   alignment: focusSquareAlignment,
                                   allowAnimation: false)

        //  load a new corresponding LeiaAU source in the AmbeoAAEngine
        ambeoEngine.load(object: virtualObject)

        updateQueue.async {
            self.sceneView.scene.rootNode.addChildNode(virtualObject)
            self.sceneView.addOrUpdateAnchor(for: virtualObject)
        }
        
    }

    // MARK: - VirtualObjectSelectionViewControllerDelegate

    /** A VirtualObject was selected. Place it in the scene. */
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didSelectObject object: VirtualObject) {
        virtualObjectLoader.loadVirtualObject(object, loadedHandler: { [unowned self] loadedObject in
            DispatchQueue.main.async {
                self.hideObjectLoadingUI()
                self.placeVirtualObject(loadedObject)
                
                // object has been placed
                self.currentUIState = UIState.uiDefault
            }
        })
        displayObjectLoadingUI()
    }

    /** A VirtualObject was deselected. Remove it from the scene. */
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didDeselectObject object: VirtualObject) {
        guard virtualObjectLoader.loadedObjects.count > 1 else {
            displayGlobalMessage("You must have at least one instrument placed while playing.")
            return
        }
        virtualObjectLoader.remove(virtualObject: object)
        selectedObject = nil
        ambeoEngine.remove(object: object)
        if let anchor = object.anchor {
            session.remove(anchor: anchor)
        }
        self.currentUIState = UIState.uiDefault
    }

    // MARK: Object Loading UI

    /** Replace source button with a progress indicator. */
    func displayObjectLoadingUI() {
        // Show progress indicator.
        self.spinner = UIActivityIndicatorView()
        self.spinner!.center = self.sourceButton.center
        self.spinner!.bounds.size = CGSize(width: self.sourceButton.bounds.width - 5, height: self.sourceButton.bounds.height - 5)
        self.sourceButton.setImage(#imageLiteral(resourceName: "buttonring"), for: [])
        self.sceneView.addSubview(self.spinner!)
        self.spinner!.startAnimating()
        sourceButton.setImage(#imageLiteral(resourceName: "buttonring"), for: [])
        sourceButton.isEnabled = false
        isRestartAvailable = false
    }

    /** Stop and hide the source button progress indicator. */
    func hideObjectLoadingUI() {
        self.spinner?.stopAnimating()
        self.spinner?.removeFromSuperview()
        self.sourceButton.setImage(#imageLiteral(resourceName: "sourceDeselected"), for: [])
        sourceButton.isEnabled = true
        isRestartAvailable = true
    }
}
