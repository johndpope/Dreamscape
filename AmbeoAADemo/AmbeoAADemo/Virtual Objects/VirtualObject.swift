/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import Foundation
import SceneKit
import ARKit

/// - Tag: VirtualObject
class VirtualObject: SCNReferenceNode {

    /**
     * Initializes the VirtualObject with a given configuration,
     * and loads its indicated audio file.
     */
    init(config: VirtualObjectConfig) {
        self.config = config
        guard let modelUrl = Bundle.main.url(forResource: "Models.scnassets/\(config.modelName)/\(config.modelName)", withExtension: "scn")
            else { fatalError("can't find expected virtual object bundle resources") }

        // load audio file
        let fileNames = config.audioFile
        for fileName in fileNames {
            guard var delim = fileName.index(of: ".") else {
                fatalError("input sound file \(String(describing: fileName)) not valid.")
            }
            let fileResource = String(fileName[..<delim])
            delim = fileName.index(delim, offsetBy: 1)
            let fileExtension = String(fileName[delim...])

            guard let fileURL = Bundle.main.url(forResource: fileResource, withExtension: fileExtension) else {
                fatalError("input sound file \(String(describing: fileName)) not found.")
            }

            do {
                let fileTry = try AVAudioFile(forReading: fileURL)
                self.audioFiles.append(fileTry)
            } catch {
                fatalError("Could not create AVAudioFile instance. error: \(error).")
            }
        }
        super.init(url: modelUrl)!
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let config: VirtualObjectConfig

    lazy var modelName: String = config.modelName

    // MARK: Audio related properties
    var leiaAUSourceID : Int32?
    var audioFiles = [AVAudioFile]()
    public var node = AVAudioPlayerNode()
    var isPlaying = false
    var isNodeAttached = false

    /** Schedule the indicated audio file and play the VirtualObject's AVAudioPlayerNode. */
    public func play(songIndex: Int, at time: AVAudioTime?) {
        node.scheduleFile(audioFiles[songIndex], at: time)
        node.play(at: time)
    }

    /** Pause the VirtualObject's AVAudioPlayerNode. */
    public func pause() {
        node.pause()
    }

    /** Stop the VirtualObject's AVAudioPlayerNode. */
    public func stop() {
        node.stop()
    }

    // MARK: Visual related properties

    /// Use average of recent virtual object distances to avoid rapid changes in object scale.
    private var recentVirtualObjectDistances = [Float]()

    /// Allowed alignments for the virtual object
    var allowedAlignments: [ARPlaneAnchor.Alignment] {
        var result: [ARPlaneAnchor.Alignment] = []
        if config.allowedAlignments.contains("horizontal") {
            result.append(.horizontal)
        }
        if config.allowedAlignments.contains("vertical") {
            result.append(.vertical)
        }
        return result
    }

    /// Current alignment of the virtual object
    var currentAlignment: ARPlaneAnchor.Alignment = .horizontal

    /// Whether the object is currently changing alignment
    private var isChangingAlignment: Bool = false

    /// For correct rotation on horizontal and vertical surfaces, roate around
    /// local y rather than world y. Therefore rotate first child node instead of self.
    var objectRotation: Float {
        get {
            return childNodes.first!.eulerAngles.y
        }
        set (newValue) {
            var normalized = newValue.truncatingRemainder(dividingBy: 2 * .pi)
            normalized = (normalized + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if normalized > .pi {
                normalized -= 2 * .pi
            }
            childNodes.first!.eulerAngles.y = normalized
            if currentAlignment == .horizontal {
                rotationWhenAlignedHorizontally = normalized
            }
        }
    }

    /// Remember the last rotation for horizontal alignment
    var rotationWhenAlignedHorizontally: Float = 0.0

    /// The object's corresponding ARAnchor
    var anchor: ARAnchor?

    /// Resets the object's position smoothing.
    func reset() {
        recentVirtualObjectDistances.removeAll()
    }

    // MARK: - Helper methods to determine supported placement options

    func isPlacementValid(on planeAnchor: ARPlaneAnchor?) -> Bool {
        if let anchor = planeAnchor {
            return allowedAlignments.contains(anchor.alignment)
        }
        return true
    }

    /**
     * Set the object's position based on the provided position relative to the `cameraTransform`.
     * If `smoothMovement` is true, the new position will be averaged with previous position to
     * avoid large jumps.
     */
    func setTransform(_ newTransform: float4x4,
                      relativeTo cameraTransform: float4x4,
                      smoothMovement: Bool,
                      alignment: ARPlaneAnchor.Alignment,
                      allowAnimation: Bool) {

        let cameraWorldPosition = cameraTransform.translation
        var positionOffsetFromCamera = newTransform.translation - cameraWorldPosition

        // Limit the distance of the object from the camera to a maximum of 10 meters.
        if simd_length(positionOffsetFromCamera) > 10 {
            positionOffsetFromCamera = simd_normalize(positionOffsetFromCamera)
            positionOffsetFromCamera *= 10
        }

        // Compute the average distance of the object from the camera over the last ten
        // updates. Notice that the distance is applied to the vector from
        // the camera to the content, so it affects only the percieved distance to the
        // object. Averaging does _not_ make the content "lag".
        if smoothMovement {
            let hitTestResultDistance = simd_length(positionOffsetFromCamera)

            // Add the latest position and keep up to 10 recent distances to smooth with.
            recentVirtualObjectDistances.append(hitTestResultDistance)
            recentVirtualObjectDistances = Array(recentVirtualObjectDistances.suffix(10))

            let averageDistance = recentVirtualObjectDistances.average!
            let averagedDistancePosition = simd_normalize(positionOffsetFromCamera) * averageDistance
            simdPosition = cameraWorldPosition + averagedDistancePosition
        } else {
            simdPosition = cameraWorldPosition + positionOffsetFromCamera
        }

        updateAlignment(to: alignment, transform: newTransform, allowAnimation: allowAnimation)

    }

    // MARK: - Setting the object's alignment

    /**
     * Update the plane alignment of the VirtualObject.
     */
    func updateAlignment(to newAlignment: ARPlaneAnchor.Alignment, transform: float4x4, allowAnimation: Bool) {
        guard !isChangingAlignment else  { return }

        // Only animate if the alignment has changed.
        let animationDuration = (newAlignment != currentAlignment && allowAnimation) ? 0.5 : 0

        var newObjectRotation: Float?
        if newAlignment == .horizontal && currentAlignment == .vertical {
            // When changing to horizontal placement, restore the previous horizontal rotation.
            newObjectRotation = rotationWhenAlignedHorizontally
        } else if newAlignment == .vertical && currentAlignment == .horizontal {
            // When changing to vertical placement, reset the object's rotation (y-up).
            newObjectRotation = 0.0001
        }

        currentAlignment = newAlignment

        SCNTransaction.begin()
        SCNTransaction.animationDuration = animationDuration
        SCNTransaction.completionBlock = {
            self.isChangingAlignment = false
        }

        isChangingAlignment = true

        // Use the filtered position rather than the exact one from the transform.
        simdTransform = transform
        simdTransform.translation = simdWorldPosition

        if newObjectRotation != nil {
            objectRotation = newObjectRotation!
        }

        SCNTransaction.commit()
    }

    /**
     * Adjust the VirtualObject's transform onto the indicated PlaneAnchor.
     */
    func adjustOntoPlaneAnchor(_ anchor: ARPlaneAnchor, using node: SCNNode) {
        // Test if the alignment of the plane is compatible with the object's allowed placement
        if !allowedAlignments.contains(anchor.alignment) {
            return
        }

        // Get the object's position in the plane's coordinate system.
        let planePosition = node.convertPosition(position, from: parent)

        // Check that the object is not already on the plane.
        guard planePosition.y != 0 else { return }

        // Add 10% tolerance to the corners of the plane.
        let tolerance: Float = 0.1

        let minX: Float = anchor.center.x - anchor.extent.x / 2 - anchor.extent.x * tolerance
        let maxX: Float = anchor.center.x + anchor.extent.x / 2 + anchor.extent.x * tolerance
        let minZ: Float = anchor.center.z - anchor.extent.z / 2 - anchor.extent.z * tolerance
        let maxZ: Float = anchor.center.z + anchor.extent.z / 2 + anchor.extent.z * tolerance

        guard (minX...maxX).contains(planePosition.x) && (minZ...maxZ).contains(planePosition.z) else {
            return
        }

        // Move onto the plane if it is near it (within 5 centimeters).
        let verticalAllowance: Float = 0.05
        let epsilon: Float = 0.001 // Do not update if the difference is less than 1 mm.
        let distanceToPlane = abs(planePosition.y)
        if distanceToPlane > epsilon && distanceToPlane < verticalAllowance {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = CFTimeInterval(distanceToPlane * 500) // Move 2 mm per second.
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            position.y = anchor.transform.columns.3.y
            updateAlignment(to: anchor.alignment, transform: simdWorldTransform, allowAnimation: false)
            SCNTransaction.commit()
        }
    }
}

extension VirtualObject {

    /** Returns a `VirtualObject` if one exists as an ancestor to the provided node. */
    static func existingObjectContainingNode(_ node: SCNNode) -> VirtualObject? {
        if let virtualObjectRoot = node as? VirtualObject {
            return virtualObjectRoot
        }
        guard let parent = node.parent else { return nil }
        // Recurse up to check if the parent is a `VirtualObject`.
        return existingObjectContainingNode(parent)
    }

}

extension Collection where Element == Float, Index == Int {

    /** Return the mean of a list of Floats. Used with `recentVirtualObjectDistances`. */
    var average: Float? {
        guard !isEmpty else {
            return nil
        }

        let sum = reduce(Float(0)) { current, next -> Float in
            return current + next
        }

        return sum / Float(count)
    }
}
