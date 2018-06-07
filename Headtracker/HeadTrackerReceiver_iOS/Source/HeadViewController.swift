/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import UIKit
import SceneKit

@available(iOS 11.0, *)
class HeadViewController: UIViewController {
  
  @IBOutlet weak var HeadView: SCNView!
  
  var headViewController : HeadViewController?
  
  override func viewDidLoad() {
    super.viewDidLoad()
    if let view = HeadView {
      let scnHead = SCNScene(named: "HeadNose-x.scn")
      view.scene = scnHead
      view.backgroundColor = UIColor.clear
      view.allowsCameraControl = false
      view.autoenablesDefaultLighting = true
      view.showsStatistics = false
      view.preferredFramesPerSecond = 12
      view.scene?.rootNode.eulerAngles = SCNVector3(0, 0, -Double.pi / 2.0)
      self.view = view
    }
    // Do any additional setup after loading the view.
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if let view = HeadView {
      view.backgroundColor = UIColor.clear
      view.setNeedsDisplay()
    }
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  func updateOrientation(yaw: Double, pitch: Double, roll: Double) {
    let pitch = Double.pi * pitch / 180.0
    let yaw = Double.pi * yaw / 180.0
    let roll = Double.pi * roll / 180.0
    
    if let view = HeadView {
      // Rotation for pitch and roll
      let qYaw = simd_quatf(angle: Float(yaw), axis: float3(x: 0.0, y: 0.0, z: 1.0))
      let qPitch = simd_quatf(angle: Float(pitch), axis: float3(x: -Float(sin(yaw)), y: Float(cos(yaw)), z: 0.0))
      let qRoll = simd_quatf(angle: Float(roll), axis: float3(x: Float(-cos(yaw)), y: Float(-sin(yaw)), z: 0.0))
      let totalOrientation = qPitch * qRoll * qYaw
      // Apply quaternion orientation to head
      let orientation : simd_quatf = simd_quatf(ix: Float(totalOrientation.imag.x ), iy: Float(totalOrientation.imag.y), iz: Float(totalOrientation.imag.z), r: Float(totalOrientation.real))
      view.scene?.rootNode.childNodes[0].simdOrientation = orientation
    }
  }
}
