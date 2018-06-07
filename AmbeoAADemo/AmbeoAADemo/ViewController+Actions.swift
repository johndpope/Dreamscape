/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// UI Actions for the main view controller.

import ARKit
import UIKit
import SceneKit

extension ViewController {

    enum SegueIdentifier: String {
        case showObjects
        case showMaterials
    }

    /**
     * Displays the `VirtualObjectSelectionViewController` from the `addObjectButton`
     * or in response to a tap gesture in the `sceneView`.
     */
    @IBAction func showVirtualObjectSelectionViewController() {
        // Ensure adding objects is an available action and we are not loading another object (to avoid concurrent modifications of the scene).
        guard !sourceButton.isHidden && !virtualObjectLoader.isLoading else { return }

        textManager.cancelScheduledMessage(forType: .contentPlacement)
        performSegue(withIdentifier: SegueIdentifier.showObjects.rawValue, sender: sourceButton)
    }

    /** Determines if the tap gesture for presenting the `VirtualObjectSelectionViewController` should be used */
    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        return virtualObjectLoader.loadedObjects.isEmpty
    }

    /**
     * Adjusts the opacity of all plane nodes.
     */
    func showPlanes(show: Bool) {
        var opacity = CGFloat(0.0)
        if show {
            opacity = CGFloat(0.25)
        }
        for anchor in (session.currentFrame?.anchors)! {
            if let node = sceneView.node(for: anchor){
                node.childNode(withName: "planeNode", recursively: false)?.opacity = opacity
            }
        }
    }

    /**
     * Toggles the plane detection option of the ARWorldTrackingConfiguration.
     */
    func togglePlaneDetection() {
        isPlaneDetectionEnabled = !isPlaneDetectionEnabled
        let configuration = ARWorldTrackingConfiguration()
        if isPlaneDetectionEnabled {
            configuration.planeDetection = [.horizontal, .vertical]
            focusSquare.unhide()
        } else {
            configuration.planeDetection = []
            focusSquare.hide()
        }
        session.run(configuration, options: [])
    }

    // MARK: - Interface Actions

    /** Toggles Debug Mode */
    @IBAction func touchDebugButton(_ button: UIButton) {
        self.toggleDebugMode()
    }

    /**
     * Displays the `VirtualObjectSelectionViewController` from the `addObjectButton`
     * or in response to a tap gesture in the `sceneView`.
     */
    func toggleDebugMode() {
        guard (self.currentUIState != UIState.uiPaintMaterial) else {
            self.displayGlobalMessage("Debug mode not available when painting materials")
            return
        }
        isDebugModeEnabled = !isDebugModeEnabled
        self.displayGlobalMessage("Debug mode: \(isDebugModeEnabled)")
        if (isDebugModeEnabled) {
            sceneView.debugOptions  = [.showConstraints, .showLightExtents, ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
            self.debugButton.setImage(#imageLiteral(resourceName: "debug"), for: [])
        } else {
            sceneView.debugOptions  = []
            self.debugButton.setImage(#imageLiteral(resourceName: "debugDeselected"), for: [])
        }
        sceneView.showsStatistics = isDebugModeEnabled
        showPlanes(show: isDebugModeEnabled)
    }

    /**
     * Segues to the source selection view controller and changes UIState accordingly.
     */
    @IBAction func touchSourceButton(_ button: UIButton) {
        guard !virtualObjectLoader.isLoading else { return }
        guard self.floorPlaneNode != nil else {
            displayGlobalMessage("Find your first surface.")
            return
        }
        guard (!isEnvironmentModeEnabled) else {
            self.displayGlobalMessage("Finish adjusting the environment before placing sources.")
            return
        }
        self.currentUIState = UIState.uiLoadObject
        textManager.cancelScheduledMessage(forType: .contentPlacement)
        performSegue(withIdentifier: SegueIdentifier.showObjects.rawValue, sender: button)
    }

    /**
     * Multifunctional handle for completing height measurement, completing material painting,
     * or displaying environment-related UIButtons and the virtual acoustic environment.
     */
    @IBAction func touchEnvironmentButton(_ button: UIButton) {
        guard self.floorPlaneNode != nil else {
            displayGlobalMessage("Find your first surface.")
            return
        }
        if (self.currentUIState == UIState.uiMeasureEnvironmentHeight) {
            // done determining environment height
            displayGlobalMessage("Environment height: \(self.shoeboxHeight) meters")
            self.currentUIState = UIState.uiDefault
            self.measureHeightButton.isHidden = false
            self.paintMaterialButton.isHidden = false
            self.lockEnvironmentButton.isHidden = false
            self.environmentButton.setImage(#imageLiteral(resourceName: "environment"), for: [])
        } else if (self.currentUIState == UIState.uiPaintMaterial) {
            // done painting materials
            self.currentUIState = UIState.uiDefault
            self.measureHeightButton.isHidden = false
            self.paintMaterialButton.isHidden = false
            self.lockEnvironmentButton.isHidden = false
            self.environmentButton.setImage(#imageLiteral(resourceName: "environment"), for: [])
            self.togglePlaneDetection()
        } else {
            self.toggleEnvironmentMode()
        }
    }

    /**
     * Toggles visibility of the virtual environment surfaces and associated UI.
     */
    func toggleEnvironmentMode() {
        isEnvironmentModeEnabled = !isEnvironmentModeEnabled
        self.displayGlobalMessage("Environment mode: \(isEnvironmentModeEnabled)")
        if (isEnvironmentModeEnabled) {
            if (isEnvironmentLocked) {
                hideLeiaShoeboxEnvironment(false)
            } else {
                updateLeiaShoeboxEnvironment()
            }
            self.environmentButton.setImage(#imageLiteral(resourceName: "environment"), for: [])
        } else {
            hideLeiaShoeboxEnvironment(true)
            self.environmentButton.setImage(#imageLiteral(resourceName: "environmentDeselected"), for: [])
        }
        self.measureHeightButton.isHidden = !self.measureHeightButton.isHidden
        self.paintMaterialButton.isHidden = !self.paintMaterialButton.isHidden
        self.lockEnvironmentButton.isHidden = !self.lockEnvironmentButton.isHidden
    }

    /**
     * Changes UIState to height measurement.
     */
    @IBAction func touchMeasureHeightButton(_ button: UIButton) {
        guard !virtualObjectLoader.isLoading else { return }
        guard !isEnvironmentLocked else {
            displayGlobalMessage("Unlock environment to measure height.")
            return
        }
        self.currentUIState = UIState.uiMeasureEnvironmentHeight
        self.measureHeightButton.isHidden = true
        self.paintMaterialButton.isHidden = true
        self.lockEnvironmentButton.isHidden = true
        self.environmentButton.setImage(#imageLiteral(resourceName: "done"), for: [])
    }

    /**
     * Changes UIState to painting of materials.
     */
    @IBAction func touchPaintMaterialButton(_ button: UIButton) {
        guard !virtualObjectLoader.isLoading else { return }
        togglePlaneDetection() // prevent shoebox from updating while we assign materials
        if (isDebugModeEnabled) { self.toggleDebugMode() }
        textManager.cancelScheduledMessage(forType: .contentPlacement)
        self.currentUIState = UIState.uiPaintMaterial
        self.measureHeightButton.isHidden = true
        self.paintMaterialButton.isHidden = true
        self.lockEnvironmentButton.isHidden = true
        self.environmentButton.setImage(#imageLiteral(resourceName: "done"), for: [])
    }

    /**
     * Toggles the prevention of automatic environment update.
     */
    @IBAction func touchLockEnvironmentButton(_ button: UIButton) {
        self.isEnvironmentLocked = !self.isEnvironmentLocked
        if (isEnvironmentLocked) {
            self.lockEnvironmentButton.setImage(#imageLiteral(resourceName: "lock"), for: [])
            displayGlobalMessage("Environment is now locked.")
        } else {
            self.lockEnvironmentButton.setImage(#imageLiteral(resourceName: "lockDeselected"), for: [])
            displayGlobalMessage("Environment is now unlocked.")
        }
    }

    /**
     * Toggles playing of the AmbeoAAEngine.
     */
    @IBAction func touchPlayButton(_ sender: Any) {
        guard !virtualObjectLoader.isLoading else { return }
        if (virtualObjectLoader.loadedObjects.count > 0) {
            DispatchQueue.main.async {
                self.ambeoEngine.updateAllObjectPositions()
            }
            if (ambeoEngine.togglePlay()) {
                if (isDebugModeEnabled) { toggleDebugMode() }
                if (isEnvironmentModeEnabled) { toggleEnvironmentMode() }
                currentUIState = UIState.uiPlay
                displayGlobalMessage("Play")
                playButton.setImage(#imageLiteral(resourceName: "stop"), for: [])
                playButton.setImage(#imageLiteral(resourceName: "stop"), for: [.highlighted])
                focusSquare.isHidden = true
                restartButton.isHidden = true
                debugButton.isHidden = true
                sourceButton.isHidden = true
                environmentButton.isHidden = true
                paintMaterialButton.isHidden = true
                measureHeightButton.isHidden = true
            } else {
                currentUIState = UIState.uiDefault
                displayGlobalMessage("Stop")
                playButton.setImage(#imageLiteral(resourceName: "play"), for: [])
                playButton.setImage(#imageLiteral(resourceName: "play"), for: [.highlighted])
                focusSquare.isHidden = false
                restartButton.isHidden = false
                debugButton.isHidden = false
                sourceButton.isHidden = false
                environmentButton.isHidden = false
            }
        } else {
            self.displayGlobalMessage("Place at least one instrument before playing")
        }
    }

    /**
     * Displays the LeiaAU control panel. This is currently only available for iPad devices.
     */
    @IBAction func touchLeiaAUButton(_ sender: Any) {
        leiaAUContainerView.isHidden = !leiaAUContainerView.isHidden
    }

    /**
     * Calls `restartExperience()`
     */
    @IBAction func touchRestartButton(_ sender: Any) {
        self.restartExperience()
    }
  
    /**
     * Restarts the application experience to its state just after the ViewController's `viewDidAppear()`.
     */
    func restartExperience() {

        guard isRestartAvailable, !virtualObjectLoader.isLoading, self.currentUIState != UIState.uiPlay else { return }

        let refreshAlert = UIAlertController(title: "Restart Experience?", message: "All session data will be lost.", preferredStyle: UIAlertControllerStyle.alert)

        refreshAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action: UIAlertAction!) in
            DispatchQueue.main.async {

                self.isRestartAvailable = false
                self.currentUIState = UIState.uiDefault
                if (self.isDebugModeEnabled) {
                    self.toggleDebugMode()
                }
                if (self.isEnvironmentModeEnabled) {
                    self.toggleEnvironmentMode()
                }

                self.textManager.cancelAllScheduledMessages()
                self.textManager.dismissPresentedAlert()
                self.displayGlobalMessage("Restarting session")

                self.ambeoEngine.stopPlaying()
                self.ambeoEngine = AmbeoAAEngine()
                self.ambeoEngine.removeAllObjects()
                self.virtualObjectLoader.removeAllVirtualObjects()
                self.floorPlaneNode = nil

                self.sourceButton.setImage(#imageLiteral(resourceName: "sourceDeselected"), for: [])
                self.measureHeightButton.setImage(#imageLiteral(resourceName: "measureHeightDeselected"), for: [])
                self.measureHeightButton.isHidden = true
                self.lockEnvironmentButton.setImage(#imageLiteral(resourceName: "lockDeselected"), for: [])
                self.lockEnvironmentButton.isHidden = true
                self.paintMaterialButton.setImage(#imageLiteral(resourceName: "paintMaterialDeselected"), for: [])
                self.paintMaterialButton.isHidden = true
                self.playButton.setImage(#imageLiteral(resourceName: "play"), for: [])
                self.restartButton.setImage(#imageLiteral(resourceName: "restart"), for: [])

                self.resetTracking()
                self.setupAudio()
                self.embedPlugInView()

                self.focusSquare.isHidden = true
                // Show the focus square after a short delay to ensure all plane anchors have been deleted.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                    self.focusSquare.isHidden = false
                    self.updateFocusSquare()
                })

                // Disable restart for a while in order to give the session time to restart.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.isRestartAvailable = true
                }
            }
        }))
        refreshAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action: UIAlertAction!) in }))

        present(refreshAlert, animated: true, completion: nil)
    }

    /**
     * Reset LeiaAU virtual acoustic environment to its default configuration.
     */
    func resetEnvironment() {
        self.hideLeiaShoeboxEnvironment(true)
        leiaAU.setLeiaAuEnvironmentFreefield()
        leiaAU.setLeiaAuEnvironmentShoeboxOrigin(0.0, 0.0, 0.0)
        leiaAU.setLeiaAuEnvironmentShoeboxOrientationEuler(0.0, 0.0, 0.0)
        ambeoEngine.updateAllObjectPositions() // update Leia object positions to default coordinate system
    }
    
}

extension ViewController: UIPopoverPresentationControllerDelegate {

    // MARK: - UIPopoverPresentationControllerDelegate

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // All menus should be popovers (even on iPhone).
        if let popoverController = segue.destination.popoverPresentationController, let button = sender as? UIButton {
            popoverController.delegate = self
            popoverController.sourceView = button
            popoverController.sourceRect = button.bounds
        }

        guard let identifier = segue.identifier,
            let segueIdentifer = SegueIdentifier(rawValue: identifier),
            segueIdentifer == .showObjects else { return }

        let objectsViewController = segue.destination as! VirtualObjectSelectionViewController
        objectsViewController.virtualObjects = VirtualObjectLoader.availableObjects
        objectsViewController.delegate = self
        self.objectsViewController = objectsViewController

        // Set all rows of currently placed objects to selected.
        for object in virtualObjectLoader.loadedObjects {
            guard let index = VirtualObjectLoader.availableObjects.index(of: object) else { continue }
            objectsViewController.selectedVirtualObjectRows.insert(index)
        }
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        objectsViewController = nil
    }

    /** Hit tests against the sceneView to find an SCNNode plane at the given point */
    func identifyVirtualPlane(at point: CGPoint, sceneView: ARSCNView) -> SCNNode? {
        let hitTestOptions: [SCNHitTestOption: Any] = [.boundingBoxOnly: true]
        let hitTestResults: [SCNHitTestResult] = sceneView.hitTest(point, options: hitTestOptions)
        return hitTestResults.lazy.flatMap { result in result.node }.first
    }

}
