/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// Uses AVAudioUnitComponentManager, AVAudioEngine, AVAudioUnit, AUAudioUnit,
// and VirtualObject to play an audio files through the LeiaAU Audio Unit.

import AVFoundation
import AudioToolbox
import LeiaAUFramework
import SceneKit

/// - Tag: AmbeoAAEngine
public class AmbeoAAEngine {

    // MARK: Properties

    /// Array of engine virtual objects that contain a player. The index of each player corresponds to the input bus number of LeiaAU to which it is attached
    private(set) var loadedObjects = [VirtualObject]()
    private var globalIdCounter = Int32(0)

    private var tempInputNode = AVAudioPlayerNode()

    /// The engine's LeiaAU.
    public var leiaAU: LeiaAU! {
        get {
            return leiaAUNode?.auAudioUnit as? LeiaAU
        }
    }

    /// Engine's LeiaAU node as an AVAudioUnit.
    private var leiaAUNode: AVAudioUnit?

    /// Synchronizes starting/stopping the engine and scheduling file segments.
    private let stateChangeQueue = DispatchQueue(label: "AmbeoAAEngine.stateChangeQueue")

    /// Internal playback engine.
    private let engine = AVAudioEngine()

    /// Array of LeiaSource IDs
    var sourceIDs = [Int32]()

    /// Whether we are playing.
    private var isPlaying = false

    /// The current song to play.
    var currentSongIndex = 0

    /// Whether we are recording.
    private var isRecording = false

    /// Whether recording is enabled.
    public var isRecordingEnabled = true

    // MARK: Recording AmbeoAAEngine to file

    var ashRecorder: AVAudioRecorder?
    var ashAudioFilename: String = "recordingASH.caf"
    var leiaAUAudioFilename: String = "recordingAA.caf"
    var leiaAUAudioFile: AVAudioFile?

    // MARK: Initialization

    /**
     * Initialize the AmbeoAAEngine.
     *
     * This sets the preferred audio processing settings of
     * the singleton AVAudioSession, loads the LeiaAU Audio
     * Unit, and begins engine rendering.
     */
    public init() {

        // Set AVAudioSession parameters
        let audioSession = AVAudioSession.sharedInstance()
        do {
          try audioSession.setCategory(AVAudioSessionCategoryMultiRoute)
          try audioSession.setPreferredSampleRate(Double(LeiaAU.sampleRate()))
          try audioSession.setPreferredIOBufferDuration(TimeInterval((1.0/LeiaAU.sampleRate()) * LeiaAU.frameCount()))
        } catch {
          fatalError("AmbeoAAEngine - Failed to initialize AVAudioSession.")
        }

        // Sign up for a notification when audio routing changes (i.e. headset is unplugged)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: .AVAudioSessionRouteChange, object: nil)

        // Sign up for a notification when an audio unit crashes.
        NotificationCenter.default.addObserver(forName: NSNotification.Name(String(kAudioComponentInstanceInvalidationNotification)), object: nil, queue: nil) { [weak self] notification in
            guard let strongSelf = self else { return }
            let crashedAU = notification.object as? AUAudioUnit
            if strongSelf.leiaAU === crashedAU {
                fatalError("AmbeoAAEngine - LeiaAU has failed.")
            }
        }

        // Load LeiaAU Audio Unit
        var componentDescription = AudioComponentDescription()
        componentDescription.componentType = kAudioUnitType_Effect
        componentDescription.componentSubType = 0x6c656961 /*'leia'*/
        componentDescription.componentManufacturer = 0x53454e4e /*'SENN'*/
        componentDescription.componentFlags = 0
        componentDescription.componentFlagsMask = 0
        AUAudioUnit.registerSubclass(LeiaAU.self, as: componentDescription, name:"AU: Local LeiaAU", version: UInt32.max)
        AVAudioUnit.instantiate(with: componentDescription, options: .loadOutOfProcess) {
            avAudioUnit, _ in
            guard let avAudioUnit = avAudioUnit else { return }

            self.leiaAUNode = avAudioUnit
            self.engine.attach(avAudioUnit)

            avAudioUnit.auAudioUnit.contextName = "AmbeoAAEngine"
            print("AmbeoAAEngine - LeiaAU Audio Unit instantiated.")
        }

        self.startRenderingInternal()
    }
    
    /**
     * Start LeiaAU rendering, and therefore also Leia parameter
     * processing. We call this immediately, at the end of `init()`.
     */
    private func startRenderingInternal() {

        setSessionActive(true)

        // Create the AMBEO Smart Headset input node. Note that, internally, the AVAudioEngine
        // creates a singleton AVAudioInputNode on demand when this property is first accessed (here).
        _ = self.engine.inputNode

        // Create the engine's main AVAudioMixerNode. Note that, internally, the AVAudioEngine constructs a singleton
        // main mixer and connects it to the outputNode on demand, when this property is first accessed (here).
        let mixerNode = self.engine.mainMixerNode

        // The Leia pipe only processes messages when the Leia audio unit's process function is called.
        // Because the listener updates are happening constantly, this means we must ensure the Leia
        // audio unit is processing constantly to take care of these messages and prevent overflow.
        // This means that we must ensure that the audio unit render callback is being called from the
        // very start -- and the only way we can make that callback fire is by providing the audio unit
        // with an input node. Otherwise, it will not call its internalRenderBlock. Therefore, this
        // temporary node is used as an initial input for the Leia audio unit (though NOT the Leia engine)
        // with an input buffer of zeros.
        self.engine.attach(tempInputNode)
        let AUInputFormat = AVAudioFormat(standardFormatWithSampleRate: Double(LeiaAU.sampleRate()), channels: 1)
        self.engine.connect(tempInputNode, to: self.leiaAUNode!, fromBus: 0, toBus: 0, format: AUInputFormat)

        // Connect stereo output of LeiaAU to input of AVAudioMixerNode
        let AUOutputFormat = leiaAUNode!.outputFormat(forBus: 0)
        self.engine.connect(leiaAUNode!, to: mixerNode, fromBus: 0, toBus: 0, format: AUOutputFormat)

        // Connect stereo output of mixer node to engine output
        self.engine.connect(mixerNode, to: self.engine.outputNode, format: mixerNode.outputFormat(forBus: 0))

        engine.prepare() // calls allocateRenderResources in LeiaAU

        do { // Start the engine
            try engine.start()
        } catch {
            fatalError("AmbeoAAEngine - Failed to start engine. \(error).")
        }
        print("AmbeoAAEngine - Now rendering.")
    }

    /** Set the session active or inactive. */
    private func setSessionActive(_ active: Bool) {
        do {
            try AVAudioSession.sharedInstance().setActive(active, with: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation)
        } catch {
            fatalError("AmbeoAAEngine - Failed to set Audio Session active \(active). error: \(error).")
        }
    }

    /**
     * Callback for any route change notifications posted by AVAudioSession.
     * This notifies us when a user connects or removes their headphones.
     *
     * Route changes occurring while the engine `isPlaying` will cause the
     * engine to stop playing. Moreover, route changes occurring while the
     * engine is rendering (`engine.isRunning`) will eventually automatically
     * trigger the engine to stop.
     */
    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSessionRouteChangeReason(rawValue:reasonValue) else {
                return
        }
        switch reason {
        case .newDeviceAvailable:
            let audioSession = AVAudioSession.sharedInstance()
            for output in audioSession.currentRoute.outputs where output.portType == AVAudioSessionPortHeadphones {
                print("New audio device connected")
                break
            }
        case .oldDeviceUnavailable:
            if let previousRoute =
                userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                for output in previousRoute.outputs where output.portType == AVAudioSessionPortHeadphones {
                    print("Audio device disconnected")
                    break
                }
            }
        default: ()
        }
    }

    /**
     * If the engine is not playing, begin playing all associated sources.
     * Otherwise, if the engine is playing, stop playing all associated sources.
     * For specific rammifications, see `startPlayingInternal()` and `stopPlayingInternal()`.
     */
    public func togglePlay() -> Bool {
        if isPlaying {
            stopPlaying()
        } else {
            startPlaying()
        }
        return isPlaying
    }

    /** If the engine is not playing, begin playing all associated sources. */
    public func startPlaying() {
        stateChangeQueue.sync {
            guard !self.isPlaying else { return }
            self.startPlayingInternal()
        }
    }

    /** If the engine is playing, stop playing all associated sources. */
    public func stopPlaying() {
        stateChangeQueue.sync {
            guard self.isPlaying else { return }
            self.stopPlayingInternal()
        }
    }

    // Path for saving/retreiving recorded audio files
    func getAudioFileURL(_ filename: String) -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let docsDirect = paths[0]
        let audioUrl = docsDirect.appendingPathComponent(filename)
        return audioUrl
    }

    /**
     * Start playing all associated sources in the AmbeoAAEngine. Additionally,
     * if the AMBEO Smart Headset is attached to the device, begin recording.
     *
     * This configures the AVAudioEngineGraph by connecting all VirtualObject
     * AVAudioPlayerNode inputs to LeiaAU. Additionally, AVAudioFiles are initialized for
     * recording the LeiaAU output and AMBEO Smart Headset microphones to files.
     */
	private func startPlayingInternal() {

        if (!engine.isRunning) {
            print("AmbeoAAEngine - Restarting the engine...")
            do {
                try engine.start()
            } catch {
                fatalError("AmbeoAAEngine - Failed to start engine. \(error).")
            }
            print("AmbeoAAEngine - Now rendering.")
        }

        // Set AMBEO Smart Headset as preferred AVAudioSession input
        let audioSession = AVAudioSession.sharedInstance()
        if let inputs = audioSession.availableInputs {
            for input in inputs {
                if (input.portType == AVAudioSessionPortHeadsetMic) {
                    do {
                        try audioSession.setPreferredInput(input)
                    } catch let error {
                        print("AmbeoAAEngine - Unable to set input. \(error)")
                    }
                    print("AmbeoAAEngine - \(audioSession.preferredInput?.portName ?? String("AVAudioSessionPortHeadsetMic")) port input established.")
                }
            }
        }

        let mixerNode = self.engine.mainMixerNode

        if (!isRecording && isRecordingEnabled) {
            // Note that this recording implementation is audio input device agnostic. In other words,
            // whether or not the AMBEO Smart Headset is connected to your device, audio will be recorded
            // to `ashAudioFilename` from whatever available input exists. Furthermore, the output of Leia will always be
            // recorded to `leiaAUAudioFilename`
            var recordingSettings = mixerNode.outputFormat(forBus: 0).settings
            recordingSettings.updateValue(false, forKey: AVLinearPCMIsNonInterleaved) // Note that AVAudioFiles cannot be non-interleaved

            // NOTE: If you want to process the AMBEO Smart Headset audio in "realtime", you must connect
            // its output (microphones) to the input of your desired processing unit(s), and the output
            // of the unit(s) to an available input bus of the mixer node (and thus ultimately the engine
            // output). Note that you should use a low `FRAME_COUNT` in LeiaAU to minimize latency. Also,
            // you should disable Transparent Hearing locally on the ASH, and effectively replace it with
            // your processed audio instead. You can do this by connecting the ASH node to the mixer like so:
            // self.engine.connect(self.engine.inputNode, to: mixerNode, fromBus: 0, toBus: mixerNode.nextAvailableInputBus, format: self.engine.inputNode.outputFormat(forBus: 0))

            do {
                try AVAudioSession.sharedInstance().setInputGain(0.75)
                // Create the ASH audio recording
                ashRecorder = try AVAudioRecorder(url: getAudioFileURL(ashAudioFilename), settings: recordingSettings)
                ashRecorder?.record()
                isRecording = true
                print("AmbeoAAEngine - Started recording.")
            } catch let error {
                print("AmbeoAAEngine - Failed to record AMBEO Smart Headset to \(ashAudioFilename). \(error)")
            }

            // Recording LeiaAU
            // If you want to record the "Augmented Audio" from
            // LeiaAU, you must install a tap on the mixer:
            do {
                try leiaAUAudioFile = AVAudioFile(forWriting: getAudioFileURL(leiaAUAudioFilename), settings: recordingSettings)
            } catch let error {
                print("AmbeoAAEngine - Failed to initialize \(leiaAUAudioFilename). \(error)")
            }
            mixerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(LeiaAU.frameCount()), format: mixerNode.outputFormat(forBus: 0)) { (buffer, time) -> Void in
                do {
                    try self.leiaAUAudioFile?.write(from: buffer)
                } catch let error {
                    print("AmbeoAAEngine - Failed to write buffer to \(self.leiaAUAudioFilename). \(error)")
                }
            }
        }

        //print(self.engine.debugDescription) // Log the resulting AVAudioEngineGraph

        // Schedule buffers on the players (synchronized at startTime)
        let now = mach_absolute_time()
        let delay = AVAudioTime.hostTime(forSeconds: 0.25)
        let startTime = AVAudioTime(hostTime: now + delay)
        for object in self.loadedObjects {
            object.play(songIndex: currentSongIndex, at: startTime)
        }

        isPlaying = true
        print("AmbeoAAEngine - Started playing.")
    }

    /**
     * Stop playing all associated sources in the AmbeoAAEngine. Additionally,
     * if the AMBEO Smart Headset is attached to the device, stop recording.
     *
     * NOTE: This function detaches all VirtualObject AVAudioPlayerNodes from
     * the AmbeoAAEngine, and disconnects all inputs to LeiaAU.
     */
    private func stopPlayingInternal() {

        // Stop all objects
        for object in loadedObjects {
            object.stop()
        }
        print("AmbeoAAEngine - Stopped playing.")

        // Stop recordings
        if (isRecording) {
            ashRecorder?.stop()
            isRecording = false
            engine.mainMixerNode.removeTap(onBus: 0)
            print("AmbeoAAEngine - Stopped recording. File writing complete.")
        }

        isPlaying = false
    }

    /**
     * Add a sound source to LeiaAU corresponding to the given VirtualObject
     *
     * The source's position and minimum distance gain limit will be determined
     * by the properties of the VirtualObject's child node LeiaAUSource "bubble"
     */
    func load(object: VirtualObject) {

        loadedObjects.append(object)

        // Create a LeiaAU source for the VirtualObject
        guard let leiaAuSource = object.childNode(withName: "LeiaAUSource", recursively: true) else {
            print("AmbeoAAEngine - WARNING: object does not have an associated LeiaAUSource.")
            return
        }

        if (loadedObjects.count == 1) {
            // Remove temporary input node
            self.engine.disconnectNodeOutput(tempInputNode)
        }
        let leiaAUinputBus = loadedObjects.count - 1
        self.engine.attach(object.node)
        let AUInputFormat = self.leiaAUNode?.inputFormat(forBus: leiaAUinputBus)
        // This will call allocateRenderResources of LeiaAU if leiaAUinputBus == 0
        self.engine.connect(object.node, to: self.leiaAUNode!, fromBus: 0, toBus: leiaAUinputBus, format: AUInputFormat)
        print("AmbeoAAEngine - Attached and connected LeiaSource \"\(object.config.displayName)\" to LeiaAU input bus \(leiaAUinputBus).")

        // add source to LeiaAU at the indicated position by the object node's
        // child LeiaAUSource "bubble", NOT the position of the object itself
        self.globalIdCounter += 1
        object.leiaAUSourceID = self.globalIdCounter
        leiaAU?.addSource(object.leiaAUSourceID!, leiaAuSource.simdPosition.x, leiaAuSource.simdPosition.y, leiaAuSource.simdPosition.z)

        // set minimum distance gain limit of the LeiaAU source
        // to the radius of the LeiaAUSource "bubble"
        if let minDistance = (leiaAuSource.geometry as? SCNSphere)?.radius {
            leiaAU?.setLeiaAuSourceMinimumDistanceGainLimit(object.leiaAUSourceID!, Float(minDistance))
        }
        leiaAuSource.isHidden = true // hide the LeiaAUSource "bubble"

    }
    
    /**
     * Remove a sound source to LeiaAU corresponding to the given VirtualObject
     */
    func remove(object: VirtualObject) {

        guard let objectIndex = loadedObjects.index(of: object) else {
            print("AmbeoAAEngine - Failed to find object in AmbeoAAEngine.")
            return
        }

        leiaAU?.removeSource(object.leiaAUSourceID!)

        self.engine.disconnectNodeInput(self.leiaAUNode!)
        self.engine.detach(object.node)
        loadedObjects.remove(at: objectIndex)
        print("AmbeoAAEngine - Disconnected and detached LeiaSource with ID \(object.leiaAUSourceID!) (\"\(object.config.displayName)\") from LeiaAU.")
        for (leiaAUinputBus, object) in self.loadedObjects.enumerated() {
            let AUInputFormat = self.leiaAUNode?.inputFormat(forBus: leiaAUinputBus)
            self.engine.connect(object.node, to: self.leiaAUNode!, fromBus: 0, toBus: leiaAUinputBus, format: AUInputFormat)
        }

        if (loadedObjects.count == 0) {
            // The only remaining object was removed. Insert temporary input node and ensure engine has stopped playing.
            // NOTE: Temporary input node has already been attached to the graph, so all we need to do is connect it.
            let AUInputFormat = AVAudioFormat(standardFormatWithSampleRate: Double(LeiaAU.sampleRate()), channels: 1)
            self.engine.connect(tempInputNode, to: self.leiaAUNode!, fromBus: 0, toBus: 0, format: AUInputFormat)
            self.stopPlaying()
            return
        }

    }

    /**
     * Remove all sound sources from LeiaAU
     */
    func removeAllObjects() {
        for object in loadedObjects {
            remove(object: object)
        }
    }

    /**
     * Update each LeiaAU sound source's position
     */
    func updateAllObjectPositions() {
        guard self.isPlaying else { return }
        for object in loadedObjects {
            if let leiaAuSource = object.childNode(withName: "LeiaAUSource", recursively: true) {
                leiaAU.setLeiaAuSourcePosition(object.leiaAUSourceID!, leiaAuSource.worldPosition.x, leiaAuSource.worldPosition.y, leiaAuSource.worldPosition.z)
            }
        }
    }
    
}
