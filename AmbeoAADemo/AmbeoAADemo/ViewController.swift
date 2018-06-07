/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// Main view controller for the AR experience.

import ARKit
import SceneKit
import UIKit
import LeiaAUFramework

/// - Tag: ViewController
class ViewController: UIViewController {

    // A custom `ARSCNView` configured for the requirements of this demo.
    @IBOutlet var sceneView: AmbeoARSCNView!

    // MARK - ARSession instance and UIState

    // Convenience accessor for the session owned by ARSCNView.
    var session: ARSession {
        return sceneView.session
    }

    var screenCenter: CGPoint {
        let bounds = sceneView.bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    // The demo's current feature state
    enum UIState: String {
        case uiDefault
        case uiLoadObject
        case uiMeasureEnvironmentHeight
        case uiPaintMaterial
        case uiPlay
    }
    var currentUIState: UIState!

    var isEnvironmentModeEnabled = false
    var isEnvironmentLocked = false
    var isPlaneDetectionEnabled = true
    var isDebugModeEnabled = false

    // MARK: - Environment Properties

    var floorPlaneNode: SCNNode?
    var currentlySelectedNode: SCNNode?

    var surfaceMaterials = [String: String]()
    var shoeboxOrigin: SCNVector3?
    var shoeboxDimensions: (width: Float, length: Float, height: Float)? = nil
    var shoeboxHeight = Float(3.0)

    static let colorPlaneHorizontal = UIColor.cyan
    static let colorPlaneVertical = UIColor.red
    static let colorPlaneFloor = UIColor.blue
    static let colorPlaneSelected = UIColor.white
    static let colorEnvironmentSurface = UIColor.gray

    // MARK: - Virtual Object Manipulation Properties

    // The view controller that displays the virtual object selection menu.
    var objectsViewController: VirtualObjectSelectionViewController?

    // Coordinates the loading and unloading of reference nodes for virtual objects.
    let virtualObjectLoader = VirtualObjectLoader()

    // Marks if the AR experience is available for restart.
    var isRestartAvailable = true

    // MARK: - Audio-related Properties

    var ambeoEngine: AmbeoAAEngine! = AmbeoAAEngine()
    var leiaAU: LeiaAU!

    // MARK: - Gesture Properties

    // Developer setting to translate assuming the detected plane extends infinitely.
    let translateAssumingInfinitePlane = false

    // The object that has been most recently intereacted with.
    // The `selectedObject` can be moved at any time with the tap gesture.
    var selectedObject: VirtualObject?

    // The object that is tracked for use by the pan and rotation gestures.
    var trackedObject: VirtualObject? {
        didSet {
            guard trackedObject != nil else { return }
            selectedObject = trackedObject
        }
    }

    // The tracked screen position used to update the `trackedObject`'s position in `updateObjectToCurrentTrackingPosition()`.
    var currentTrackingPosition: CGPoint?

    // MARK: - Other Properties

    var textManager: TextManager!

    // MARK: - UI Elements

    var focusSquare = FocusSquare()
    var spinner: UIActivityIndicatorView?

    @IBOutlet weak var messagePanel: UIView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var sourceButton: UIButton!
    @IBOutlet weak var environmentButton: UIButton!
    @IBOutlet weak var lockEnvironmentButton: UIButton!
    @IBOutlet weak var paintMaterialButton: UIButton!
    @IBOutlet weak var measureHeightButton: UIButton!
    @IBOutlet weak var restartButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var leiaAUButton: UIButton!
    @IBOutlet weak var debugButton: UIButton!

    @IBOutlet var leiaAUContainerView: UIView! // container for the LeiaAU plugin view
    @IBOutlet weak var blurEffectView: UIVisualEffectView!

    // A serial queue used to coordinate adding or removing nodes from the scene.
    let updateQueue = DispatchQueue(label: "com.example.apple-samplecode.arkitexample.serialSceneKitQueue")

    // MARK: - View Controller Life Cycle

    /**
     * Called after the view has loaded.
     *
     * Sets the ViewController as the AmbeoARSCNView and ARSession
     * delegate, and calls setup functions for the user interface,
     * AmbeoAAEngine, LeiaAU, and gesture interaction.
     */
    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self
        sceneView.session.delegate = self

        // Get a notification when the user changes an environment material
        NotificationCenter.default.addObserver(self, selector: #selector(self.materialChanged(notification:)), name: Notification.Name("materialChanged"), object: nil)

        setupScene()
        focusSquare.hide()
        sceneView.scene.rootNode.addChildNode(focusSquare)
        
        setupUIControls()
        setupAudio()
        embedPlugInView()
        setupGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true // Prevent screen-dimming
        resetTracking() // Start our ARSession
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any data and assets that we are not using
        NSLog("WARNING: didReceiveMemoryWarning")
    }

    // MARK: - Setup

    /**
     * Enables HDR camera settings for the most realistic appearance
     * with environmental lighting and physically based materials.
     */
    func setupCamera() {
        guard let camera = sceneView.pointOfView?.camera else {
            fatalError("Expected a valid `pointOfView` from the scene.")
        }
        camera.wantsHDR = true
        camera.exposureOffset = -1
        camera.minimumExposure = -1
        camera.maximumExposure = 3
    }

    /**
     * Configures SCNCamera and AmbeoARSCNView lighting options.
     */
    func setupScene() {
        setupCamera()

        // The `sceneView.automaticallyUpdatesLighting` option creates an
        // ambient light source and modulates its intensity. This sample app
        // instead modulates a global lighting environment map for use with
        // physically based materials, so disable automatic lighting.
        sceneView.automaticallyUpdatesLighting = false
        if let environmentMap = UIImage(named: "Models.scnassets/sharedImages/environment_blur.exr") {
            sceneView.scene.lightingEnvironment.contents = environmentMap
        }
    }

    /**
     * Creates the TextManager and sets the default UIState
     */
    func setupUIControls() {
        textManager = TextManager(viewController: self)
        
        // Set appearance of message output panel
        messagePanel.layer.cornerRadius = 3.0
        messagePanel.clipsToBounds = true
        messagePanel.isHidden = true
        messageLabel.text = ""
        
        currentUIState = UIState.uiDefault
    }

    /**
     * Obtains access to the AmbeoAAEngine's LeiaAU Audio Unit
     */
    func setupAudio() {
        self.leiaAU = ambeoEngine.leiaAU
        if self.leiaAU == nil {
            fatalError("Expected a valid LeiaAU from the AmbeoAAEngine.")
        }
    }

    /**
     * Called from `viewDidLoad(_:)` to embed the plug-in's view into the app's view
     */
    func embedPlugInView() {
        leiaAUContainerView.translatesAutoresizingMaskIntoConstraints = false

        /*
         Locate the app extension's bundle, in the app bundle's PlugIns
         subdirectory. Load its MainInterface storyboard, and obtain the
         `LeiaAUViewController` from that.
         */
        let builtInPlugInsURL = Bundle.main.builtInPlugInsURL!
        let pluginURL = builtInPlugInsURL.appendingPathComponent("LeiaAUAppExtension.appex")
        let appExtensionBundle = Bundle(url: pluginURL)

        let auStoryboard = UIStoryboard(name: "MainInterface", bundle: appExtensionBundle)
        let leiaAUViewController = auStoryboard.instantiateInitialViewController() as? LeiaAUViewController
        leiaAUViewController?.leiaAU = ambeoEngine.leiaAU

        // Present the view controller's view.
        if let view = leiaAUViewController?.view {
            addChildViewController(leiaAUViewController!)
            view.frame = leiaAUContainerView.bounds
            leiaAUContainerView.addSubview(view)
            leiaAUViewController?.didMove(toParentViewController: self)
        }

        leiaAUContainerView.layer.borderWidth = 1
        leiaAUContainerView.layer.borderColor = UIColor.black.cgColor
        leiaAUContainerView.isHidden = true

        // AU Control Panel currently supported on iPad only
        if UIDevice.current.userInterfaceIdiom == .phone {
            leiaAUButton.isHidden = true
        }
    }

    /**
     * Creates a new ARWorldTrackingConfiguration to run on the session
     */
    func resetTracking() {
        selectedObject = nil

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        textManager.scheduleMessage("Find a surface to place an instrument", inSeconds: 7.5, messageType: .planeEstimation)
    }

    // MARK: - Focus Square

    /**
     * Updates the FocusSquare state and visibility in response to user actions.
     */
    func updateFocusSquare() {
        let isObjectVisible = virtualObjectLoader.loadedObjects.contains { object in
            return sceneView.isNode(object, insideFrustumOf: sceneView.pointOfView!)
        }
        if isObjectVisible {
            focusSquare.hide()
        } else {
            focusSquare.unhide()
            textManager.scheduleMessage("Try moving around", inSeconds: 5.0, messageType: .focusSquare)
        }
        if let result = self.sceneView.smartHitTest(screenCenter) {
            updateQueue.async {
                self.sceneView.scene.rootNode.addChildNode(self.focusSquare)
                let camera = self.session.currentFrame?.camera
                self.focusSquare.state = .detecting(hitTestResult: result, camera: camera)
            }
        } else {
            updateQueue.async {
                self.focusSquare.state = .initializing
                self.sceneView.pointOfView?.addChildNode(self.focusSquare)
            }
            return
        }
        textManager.cancelScheduledMessage(forType: .focusSquare)
    }

    // MARK - console and TextManager messaging

    /**
     * Prints the given message to both the TextManager and the console.
     */
    func displayGlobalMessage(_ message: String) {
        print(message)
        self.textManager.showMessage(message)
    }

    // MARK: - Error handling

    /**
     * Displays an error message alert.
     */
    func displayErrorMessage(title: String, message: String, allowRestart: Bool = false) {
        // Blur the background.
        textManager.blurBackground()
        blurEffectView.isHidden = false
        if allowRestart {
            // Present an alert informing about the error that has occurred.
            let restartAction = UIAlertAction(title: "Reset", style: .default) { _ in
                self.textManager.unblurBackground()
                self.blurEffectView.isHidden = true
                self.touchRestartButton(self)
            }
            textManager.showAlert(title: title, message: message, actions: [restartAction])
        } else {
            textManager.showAlert(title: title, message: message, actions: [])
        }
    }

}
