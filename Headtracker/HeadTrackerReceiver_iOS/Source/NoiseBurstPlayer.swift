/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import AVFoundation
import UIKit

/** Plays a noise burst through Leia AudioUnit, taking into account the current listener orientation */
class NoiseBurstPlayer {
  
  let file = "NoiseBurst";
  let sampleRate = 44100.0;
  let bufferSize = 512;
  
  let session = AVAudioSession.sharedInstance()
  let engine = AVAudioEngine()
  let player = AVAudioPlayerNode()
  var audioFile : AVAudioFile? = nil
  var leiaAUNode : AVAudioUnit? = nil
  
  init() {
    // Sign up for a notification when an audio unit crashes.
    NotificationCenter.default.addObserver(forName: NSNotification.Name(String(kAudioComponentInstanceInvalidationNotification)), object: nil, queue: nil) {
      [weak self] notification in
      guard let strongSelf = self else { return }
      let crashedAU = notification.object as? AUAudioUnit
      if strongSelf.leiaAUNode === crashedAU {
        fatalError("LeiaAU has failed.")
      }
    }
    
    initAudioSession()
    setupEngine()
    startEngine()
  }
  
  
  func initAudioSession() {
    do {
      try! session.setActive(false)
      try! session.setCategory(AVAudioSessionCategoryPlayAndRecord, with: [.allowBluetoothA2DP])
      try! session.setMode(AVAudioSessionModeDefault)
      try! session.setPreferredSampleRate(sampleRate)
      try! session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
      try! session.setActive(true)
    }
  }
  
  func setupEngine() {
    // Load demo audio file and setup audioEngine
    let fileURL = URL(fileURLWithPath: Bundle.main.path(forResource: file, ofType: "m4a")!)
    do {
      try? audioFile = AVAudioFile(forReading: fileURL)
    }
    guard audioFile != nil else { print("Error reading audio file"); exit(0) }
    let format = audioFile!.processingFormat
    let mainMixer = engine.mainMixerNode
    self.engine.attach(self.player)
    
    // Insert leiaAU Audio Unit
    let leiaAU = AudioComponentDescription(componentType:         kAudioUnitType_Effect,
                                           componentSubType:      0x6c656961 /*'leia'*/,
                                           componentManufacturer: 0x53454e4e /*'SENN'*/,
                                           componentFlags:        0,
                                           componentFlagsMask:    0)
    AUAudioUnit.registerSubclass(LeiaAudioUnit.self, as: leiaAU, name:"Leia", version: UInt32.max)
    let availableLeiaEffects: [AVAudioUnitComponent] = AVAudioUnitComponentManager.shared().components(matching: leiaAU)
    guard (availableLeiaEffects.count >= 1) else { print("Leia effect not found"); return }
    AVAudioUnit.instantiate(with: leiaAU, options: []) {
      avLeiaAudioUnit, _ in
      guard let avLeiaAudioUnit = avLeiaAudioUnit  else { print("Cannot proceed"); return }
      self.leiaAUNode = avLeiaAudioUnit
      print("Successfully instantiated leiaAudioUnit")
      self.engine.attach(avLeiaAudioUnit)
      self.engine.connect(self.player, to: self.leiaAUNode!, fromBus: 0, toBus: 0, format: format)
      self.engine.connect(self.leiaAUNode!, to: mainMixer, fromBus: 0, toBus: mainMixer.nextAvailableInputBus, format: format)
      
      self.engine.prepare()
    }
  }
  
  func startEngine() {
    do { // Start the engine
      try self.engine.start()
    } catch {
      fatalError("Failed to start engine. \(error).")
    }
    print("leiaAudioUnit: engine started\n")
  }
  
  func prepareAudio() {
    // Prepare audio file for playback
    player.scheduleFile(audioFile!, at: nil)
    player.prepare(withFrameCount: 10)
  }
  
  func play() {
    if (player.isPlaying) { stop() }
    prepareAudio()
    player.play()
  }
  
  func stop() {
    player.stop()
  }
  
  func updateListenerOrientation(yaw : Double, pitch : Double, roll: Double) {    
    self.leiaAUNode?.auAudioUnit.parameterTree?.parameter(withAddress:paramIDLeiaListenerYaw)?.setValue(Float(yaw), originator: nil)
    self.leiaAUNode?.auAudioUnit.parameterTree?.parameter(withAddress:paramIDLeiaListenerPitch)?.setValue(Float(pitch), originator: nil)
    self.leiaAUNode?.auAudioUnit.parameterTree?.parameter(withAddress:paramIDLeiaListenerRoll)?.setValue(Float(roll), originator: nil)
  }
}
