/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import UIKit
import CoreBluetooth
import BLEHeadtracker

class ViewController: UIViewController,  BLETrackerReceiverDelegate {
  
  var trackerReceiver : BLETrackerReceiver!   // Instance of the BLE tracker
  var noiseBurstPlayer : NoiseBurstPlayer!
  
  // Views
  var headViewController : HeadViewController?
  
  @IBOutlet weak var ValueLabelID: UITextField!
  @IBOutlet weak var ValueLabelVoltage: UITextField!
  @IBOutlet weak var ValueLabelAx: UITextField!
  @IBOutlet weak var ValueLabelAy: UITextField!
  @IBOutlet weak var ValueLabelAz: UITextField!
  @IBOutlet weak var ValueLabelAPitch: UITextField!
  @IBOutlet weak var ValueLabelARoll: UITextField!
  
  @IBOutlet weak var ValueLabelGx: UITextField!
  @IBOutlet weak var ValueLabelGy: UITextField!
  @IBOutlet weak var ValueLabelGz: UITextField!
  
  @IBOutlet weak var ValueLabelMx: UITextField!
  @IBOutlet weak var ValueLabelMy: UITextField!
  @IBOutlet weak var ValueLabelMz: UITextField!
  
  @IBOutlet weak var ValueLabelMOffsetX: UITextField!
  @IBOutlet weak var ValueLabelMOffsetY: UITextField!
  @IBOutlet weak var ValueLabelMOffsetZ: UITextField!
  
  @IBOutlet weak var ValueLabelMagneticYaw: UITextField!
  
  @IBOutlet weak var ValueLabelYaw: UITextField!
  @IBOutlet weak var ValueLabelPitch: UITextField!
  @IBOutlet weak var ValueLabelRoll: UITextField!
  
  @IBOutlet weak var yawSlider: UISlider!
  @IBOutlet weak var pitchSlider: UISlider!
  @IBOutlet weak var rollSlider: UISlider!
  
  @IBOutlet weak var statusLabel: UILabel!
  @IBOutlet weak var updateRateLabel: UILabel!
  @IBOutlet weak var CalibrationLabel1: UILabel!
  @IBOutlet weak var CalibrationLabel2: UILabel!
  
  var yaw : Float = 0.0
  var pitch : Float = 0.0
  var roll : Float = 0.0
  var isDataValid : Bool = false
  
  var isNoiseBurstPlaying : Bool = false
  var timer : Timer!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view, typically from a nib.
    trackerReceiver = BLETrackerReceiver(delegate: self)
    noiseBurstPlayer = NoiseBurstPlayer()
    
    headViewController = self.childViewControllers[0] as? HeadViewController
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
    timer.invalidate()
  }
  
  @IBAction func resetHeading(_ sender: UIButton) {
    trackerReceiver.resetHeading()
  }
  
  @IBAction func onCalibrateButton(_ sender: UIButton) {
    trackerReceiver.resetCalibration()
  }
  
  @IBAction func onTrackerOrientationChange(_ sender: UISegmentedControl) {
    switch (sender.selectedSegmentIndex) {
    case 0:
      trackerReceiver.setTrackerMountingPosition(position : TrackerMounting.FrontOfHead)
      break
    case 1:
      trackerReceiver.setTrackerMountingPosition(position : TrackerMounting.BackOfHead)
      break
    default:
      trackerReceiver.setTrackerMountingPosition(position : TrackerMounting.FrontOfHead)
      break
    }
  }
  
  @IBAction func onTouchPlayButton(_ sender: UIButton) {
    self.isNoiseBurstPlaying = !self.isNoiseBurstPlaying
    if self.isNoiseBurstPlaying {
      // Scheduling timer to Call the function "playNoiseBurst" with the interval of 2 seconds
      timer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(playNoiseBurst), userInfo: nil, repeats: true)
      sender.setImage(#imageLiteral(resourceName: "stop"), for: [])
      sender.setImage(#imageLiteral(resourceName: "stop"), for: [.highlighted])
    } else {
      timer.invalidate()
      sender.setImage(#imageLiteral(resourceName: "play"), for: [])
      sender.setImage(#imageLiteral(resourceName: "play"), for: [.highlighted])
    }    
  }
  
  @objc func playNoiseBurst() {
    noiseBurstPlayer.play()
  }
  
  
  @IBAction func onYawSliderChange(_ sender: UISlider) {
    self.yaw = sender.value
    headViewController?.updateOrientation(yaw: Double(self.yaw), pitch: Double(self.pitch), roll: Double(self.roll))
  }
  
  @IBAction func onPitchSliderChange(_ sender: UISlider) {
    self.pitch = sender.value
    headViewController?.updateOrientation(yaw: Double(self.yaw), pitch: Double(self.pitch), roll: Double(self.roll))
  }
  
  @IBAction func onRollSliderChange(_ sender: UISlider) {
    self.roll = sender.value
    headViewController?.updateOrientation(yaw: Double(self.yaw), pitch: Double(self.pitch), roll: Double(self.roll))
  }
  
  //MARK: - BLETracker Receiver Delegate functions
  func updateStatus(status: String, updateRate: String, validData: Bool, isCalibrating: Bool) {
    CalibrationLabel1.isHidden = !isCalibrating
    CalibrationLabel2.isHidden = !isCalibrating
    statusLabel.text = status
    print(status + ": " + updateRate)
    updateRateLabel.text = updateRate
    ValueLabelID.isHidden = !validData
    ValueLabelAx.isHidden = !validData
    ValueLabelAy.isHidden = !validData
    ValueLabelAz.isHidden = !validData
    
    ValueLabelGx.isHidden = !validData
    ValueLabelGy.isHidden = !validData
    ValueLabelGz.isHidden = !validData
    ValueLabelMx.isHidden = !validData
    ValueLabelMy.isHidden = !validData
    ValueLabelMz.isHidden = !validData
    ValueLabelMOffsetX.isHidden = !validData
    ValueLabelMOffsetY.isHidden = !validData
    ValueLabelYaw.isHidden = !validData
    ValueLabelPitch.isHidden = !validData
    ValueLabelRoll.isHidden = !validData
  }
  
  func updateRawData(id: Int32, trackerRawData: TrackerRawDataType) {
    ValueLabelID.text = String("\(id)")
    if (trackerRawData.voltage > 4.1) {
      ValueLabelVoltage.text = String("Full")
      ValueLabelVoltage.textColor = UIColor.green
    }
    else if (trackerRawData.voltage > 3.9) {
      ValueLabelVoltage.text = String("Good")
      ValueLabelVoltage.textColor = UIColor.green
    }
    else if (trackerRawData.voltage > 3.8) {
      ValueLabelVoltage.text = String("Fair")
      ValueLabelVoltage.textColor = UIColor.orange
    }
    else if (trackerRawData.voltage > 3.7) {
      ValueLabelVoltage.text = String("Low")
      ValueLabelVoltage.textColor = UIColor.red
    }
    else if (trackerRawData.voltage < 3.7) {
      ValueLabelVoltage.text = String("Charge!")
      ValueLabelVoltage.textColor = UIColor.red
    }

    ValueLabelAx.text = String("\(round(trackerRawData.a.x))")
    ValueLabelAy.text = String("\(round(trackerRawData.a.y))")
    ValueLabelAz.text = String("\(round(trackerRawData.a.z))")
    ValueLabelAPitch.text = String("\(round(trackerRawData.attitude.pitch))")
    ValueLabelARoll.text = String("\(round(trackerRawData.attitude.roll))")
    ValueLabelGx.text = String("\(round(trackerRawData.g.x))")
    ValueLabelGy.text = String("\(round(trackerRawData.g.y))")
    ValueLabelGz.text = String("\(round(trackerRawData.g.z))")
    ValueLabelMx.text = String("\(round(trackerRawData.mScale.x * Double(trackerRawData.m.x - trackerRawData.mOffset.x)))")
    ValueLabelMy.text = String("\(round(trackerRawData.mScale.y * Double(trackerRawData.m.y - trackerRawData.mOffset.y)))")
    ValueLabelMz.text = String("\(round(trackerRawData.mScale.z * Double(trackerRawData.m.z - trackerRawData.mOffset.z)))")
    ValueLabelMOffsetX.text = String("\(round(trackerRawData.mOffset.x))")
    ValueLabelMOffsetY.text = String("\(round(trackerRawData.mOffset.y))")
    ValueLabelMOffsetZ.text = String("\(round(trackerRawData.mOffset.z))")
    ValueLabelMagneticYaw.text = String("\(round(trackerRawData.magneticYaw))")
  }
  
  func updateAttitude(yaw: Double, pitch: Double, roll: Double)
  {
    ValueLabelYaw.text = String("\(Int(round(yaw)))")
    ValueLabelPitch.text = String("\(Int(round(pitch)))")
    ValueLabelRoll.text = String("\(Int(round(roll)))")
    yawSlider.value = Float(yaw)
    pitchSlider.value = Float(pitch)
    rollSlider.value = Float(roll)
    if (trackerReceiver.isYawCalibrated()) {
      ValueLabelYaw.textColor = UIColor.white
    }
    else {
      ValueLabelYaw.textColor = UIColor.red
    }
    if (trackerReceiver.isPitchCalibrated()) {
      ValueLabelPitch.textColor = UIColor.white
    }
    else {
      ValueLabelPitch.textColor = UIColor.red
    }
    if (trackerReceiver.isRollCalibrated()) {
      ValueLabelRoll.textColor = UIColor.white
    }
    else {
      ValueLabelRoll.textColor = UIColor.red
    }
    self.yaw = Float(yaw)
    self.pitch = Float(pitch)
    self.roll = Float(roll)
    headViewController?.updateOrientation(yaw: yaw, pitch: pitch, roll: roll)
    
    noiseBurstPlayer.updateListenerOrientation(yaw: yaw, pitch: pitch, roll: roll)
  }
  
}

extension String {
  func contains(find: String) -> Bool{
    return self.range(of: find) != nil
  }
  func containsIgnoringCase(find: String) -> Bool{
    return self.range(of: find, options: .caseInsensitive) != nil
  }
}

