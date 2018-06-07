/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

#import "LeiaAudioUnit.h"

#import <AVFoundation/AVFoundation.h>

#include "SennheiserAmbeoLeia.h" // C API

static const LeiaSampleRate SAMPLE_RATE = SAMPLERATE_44100;
static const int MAX_BLOCK_SIZE = 512;
static const int NUM_INPUTS = 2;
static const int NUM_OUTPUTS = 2;
static const int MAX_NUM_SOURCES = 2;

// Define parameter addresses.
const AUParameterAddress paramIDLeiaListenerYaw = 0;
const AUParameterAddress paramIDLeiaListenerPitch = 1;
const AUParameterAddress paramIDLeiaListenerRoll = 2;


// MARK: - LeiaAU

@interface LeiaAudioUnit ()

@property (nonatomic, readwrite) AUParameterTree *parameterTree;
@property AUAudioUnitBus *inputBus;
@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *inputBusArray;
@property AUAudioUnitBusArray *outputBusArray;
@property AUAudioChannelCount channelCountInput;
@property AUAudioChannelCount channelCountOutput;
@end


@implementation LeiaAudioUnit {
  // C members need to be ivars; they would be copied on access if they were properties.
  LeiaInstance* _leiaEngine;
  int _leiaSourceIDs[MAX_NUM_SOURCES];
  AudioBufferList* _renderABL;
  float* _leiaInBufferPointers[NUM_INPUTS];
  float** _leiaOutBuffers;
  bool leiaInitialized;
  
  AUValue _listenerYaw;
  AUValue _listenerPitch;
  AUValue _listenerRoll;
}

@synthesize parameterTree = _parameterTree;

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription options:(AudioComponentInstantiationOptions)options error:(NSError **)outError {
  self = [super initWithComponentDescription:componentDescription options:options error:outError];
  if (self == nil) {
    return nil;
  }
  
  leiaInitialized = false;
  
  self.maximumFramesToRender = MAX_BLOCK_SIZE;
  
  // Initialize a default format for the busses.
  AVAudioFormat *defaultFormatInput = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(float) SAMPLE_RATE channels: NUM_INPUTS];
  AVAudioFormat *defaultFormatOutput = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:(float) SAMPLE_RATE channels: NUM_OUTPUTS];
  
  // Create parameter objects.
  AUParameter *paramListenerYaw = [AUParameterTree createParameterWithIdentifier:@"leiaListenerYaw" name:@"Leia Listener Orientation: Yaw angle" address:paramIDLeiaListenerYaw min:0 max:360 unit:kAudioUnitParameterUnit_Degrees unitName:nil flags:0 valueStrings:nil dependentParameters:nil];
  AUParameter *paramListenerPitch = [AUParameterTree createParameterWithIdentifier:@"leiaListenerPitch" name:@"Leia Listener Orientation: Pitch angle" address:paramIDLeiaListenerPitch min:-90 max:90 unit:kAudioUnitParameterUnit_Degrees unitName:nil flags:0 valueStrings:nil dependentParameters:nil];
  AUParameter *paramListenerRoll = [AUParameterTree createParameterWithIdentifier:@"leiaListenerRoll" name:@"Leia Listener Orientation: Roll angle" address:paramIDLeiaListenerRoll min:-180 max:-180 unit:kAudioUnitParameterUnit_Degrees unitName:nil flags:0 valueStrings:nil dependentParameters:nil];
  
  // Initialize the parameter values.
  paramListenerYaw.value = 0.0;
  paramListenerPitch.value = 0.0;
  paramListenerRoll.value = 0.0;
  
  // Create the parameter tree.
  _parameterTree = [AUParameterTree createTreeWithChildren:@[ paramListenerYaw, paramListenerPitch, paramListenerRoll]];
  
  // Create the input and output busses.
  _inputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormatInput error:nil];
  _outputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormatOutput error:nil];
  
  // Create the input and output bus arrays.
  _inputBusArray  = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput busses: @[_inputBus]];
  _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses: @[_outputBus]];
  
  // Add getter and setters for each parameter
  __weak LeiaAudioUnit* weakSelf = self;
  _parameterTree.implementorValueObserver = ^(AUParameter * _Nonnull param, AUValue value) {
    switch(param.address) {
      case paramIDLeiaListenerYaw:
        self->_listenerYaw = value;
        [weakSelf updateListenerOrientation];
        break;
      case paramIDLeiaListenerPitch:
        self->_listenerPitch = value;
        [weakSelf updateListenerOrientation];
        break;
      case paramIDLeiaListenerRoll:
        self->_listenerRoll = value;
        [weakSelf updateListenerOrientation];
        break;
    };
  };
  
  _parameterTree.implementorValueProvider = ^AUValue(AUParameter * _Nonnull param) {
    switch(param.address) {
      case paramIDLeiaListenerYaw:
        return _listenerYaw;
        break;
      case paramIDLeiaListenerPitch:
        return _listenerPitch;
        break;
      case paramIDLeiaListenerRoll:
        return _listenerRoll;
        break;
      default:
        return (AUValue) 0.0;
        break;
    };
  };
  
  // A function to provide string representations of parameter values.
  _parameterTree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
    AUValue value = valuePtr == nil ? param.value : *valuePtr;
    
    switch (param.address) {
      case paramIDLeiaListenerYaw:
      case paramIDLeiaListenerPitch:
      case paramIDLeiaListenerRoll:
        return [NSString stringWithFormat:@"%.f%%", value];

      default:
        return @"?";
    }
  };
  
  // Instantiate Leia
  _leiaEngine = leia_new(SAMPLERATE_44100, MAX_BLOCK_SIZE);
  
  // Create 2 sources, and position them in the front of the listener
  _leiaSourceIDs[0] = 0;
  leia_source_add(_leiaEngine, _leiaSourceIDs[0], 0.0, 5.0, 2.0);
  _leiaSourceIDs[1] = 1;
  leia_source_add(_leiaEngine, _leiaSourceIDs[1], 0.0, 5.0, 2.0);
  
  return self;
}

// MARK: - AUAudioUnit Overrides

// If an audio unit has input, an audio unit's audio input connection points.
// Subclassers must override this property getter and should return the same object every time.
// See sample code.
- (AUAudioUnitBusArray *)inputBusses {
  return _inputBusArray;
}

// An audio unit's audio output connection points.
// Subclassers must override this property getter and should return the same object every time.
// See sample code.
- (AUAudioUnitBusArray *)outputBusses {
  return _outputBusArray;
}

// Allocate resources required to render.
// Subclassers should call the superclass implementation. Hosts must call this to initialize the AU before beginning to render.
- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
  if (![super allocateRenderResourcesAndReturnError:outError]) {
    return NO;
  }
  // Leia output buffers
  _leiaOutBuffers = (float**) malloc(NUM_OUTPUTS * sizeof(float*));
  for (int i = 0; i < NUM_OUTPUTS; i++) {
    _leiaOutBuffers[i] = (float*) malloc(MAX_BLOCK_SIZE * sizeof(float));
    memset(_leiaOutBuffers[i], 0, MAX_BLOCK_SIZE * sizeof(float));
  }

  self.channelCountInput = self.inputBus.format.channelCount;
  self.channelCountOutput = self.outputBus.format.channelCount;

  _renderABL = (AudioBufferList*) malloc(sizeof(AudioBufferList) * NUM_INPUTS);
  _renderABL->mNumberBuffers = NUM_INPUTS; // 2 for stereo, 1 for mono
  for(int i = 0; i < NUM_INPUTS; i++) {
    _renderABL->mBuffers[i].mNumberChannels = 1;
    _renderABL->mBuffers[i].mDataByteSize = MAX_BLOCK_SIZE * sizeof(float);
    _renderABL->mBuffers[i].mData = (float*) malloc(MAX_BLOCK_SIZE * sizeof(float));
  }

  leiaInitialized = true;
  
  return YES;
}

// Deallocate resources allocated by allocateRenderResourcesAndReturnError:
// Subclassers should call the superclass implementation. Hosts should call this after finishing rendering.
- (void)deallocateRenderResources {
  leiaInitialized = false;

  leia_delete(_leiaEngine);

  for (int i = 0; i < NUM_OUTPUTS; i++) {
    free(_leiaOutBuffers[i]);
  }
  free(_leiaOutBuffers);
  
  for(int i = 0; i < NUM_INPUTS; i++) {
    free(_renderABL->mBuffers[i].mData);
  }
  free(_renderABL);
  
  [super deallocateRenderResources];
}

// MARK: - AUAudioUnit (Optional Properties)

/** Expresses whether an audio unit can process in place.
 In-place processing is the ability for an audio unit to transform an input signal to an output signal in-place
 in the input buffer, without requiring a separate output buffer.
 The Leia engine, and thus the audio unit, cannot process in place.
 */
- (BOOL)canProcessInPlace {
  return NO;
}

// MARK: - AUAudioUnit (AUAudioUnitImplementation)
// Block which subclassers must provide to implement rendering.
- (AUInternalRenderBlock)internalRenderBlock {
  
  // Capture in locals to avoid ObjC member lookups. If "self" is captured in render, we're doing it wrong. See sample code.
  // Specify captured objects are mutable.
  AudioBufferList **renderABLCapture = &_renderABL;
  float **leiaInBuffersCapture = _leiaInBufferPointers;
  float ***leiaOutBuffersCapture = &_leiaOutBuffers;
  const int *leiaSourceIDsCapture = _leiaSourceIDs;
  LeiaInstance *leiaEngineCapture = _leiaEngine;
  bool *leiaInitCapture = &leiaInitialized;
  
  return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *timestamp,
                            AVAudioFrameCount frameCount, NSInteger outputBusNumber,
                            AudioBufferList *outputData, const AURenderEvent *realtimeEventListHead,
                            AURenderPullInputBlock pullInputBlock) {

    // consume the input
    pullInputBlock(actionFlags, timestamp, frameCount, 0, *renderABLCapture);
    
    if (frameCount != MAX_BLOCK_SIZE) {
      NSLog(@"frameCount of %d != %d\n", frameCount, MAX_BLOCK_SIZE);
      exit(0);
    }
    
    /*
     Important:
     If the caller passed non-null output pointers (outputData->mBuffers[x].mData), use those.
     
     If the caller passed null output buffer pointers, process in memory owned by the Audio Unit
     and modify the (outputData->mBuffers[x].mData) pointers to point to this owned memory.
     The Audio Unit is responsible for preserving the validity of this memory until the next call to render,
     or deallocateRenderResources is called.
     
     If your algorithm cannot process in-place, you will need to preallocate an output buffer and use it here.
     
     See the description of the canProcessInPlace property.
    */
    
    // If passed null output buffer pointers, process in-place in the input buffer.
    AudioBufferList *outAudioBufferList = outputData;
    if (outAudioBufferList->mBuffers[0].mData == NULL) {
      for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
        outAudioBufferList->mBuffers[i].mData = (*renderABLCapture)->mBuffers[i].mData;
      }
    }
    
    if (*leiaInitCapture) {
      
      // Assign pointers from input ABL
      for (int channel = 0; channel < outAudioBufferList->mNumberBuffers; ++channel) {
        leiaInBuffersCapture[channel] = (*renderABLCapture)->mBuffers[channel].mData;
      }

      // process Leia
      leia_process(leiaEngineCapture, leiaSourceIDsCapture, (const float**) leiaInBuffersCapture, (float**) (*leiaOutBuffersCapture), frameCount);
      
      // copy from output buffers to output ABL
      for (int channel = 0; channel < outAudioBufferList->mNumberBuffers; ++channel) {
        memcpy(outAudioBufferList->mBuffers[channel].mData, (*leiaOutBuffersCapture)[channel], frameCount * sizeof(float));
      }
      
    } else {
      /* BYPASS, copy first input to all outputs */
      float* input  = (float*)(*renderABLCapture)->mBuffers[0].mData;
      for (int channel = 0; channel < self.channelCountOutput; ++channel) {
        float* output = (float*) outAudioBufferList->mBuffers[channel].mData;
        memcpy(output, input, frameCount * sizeof(float));
      }
    }
    return noErr;
  };
}

// MARK: - Leia related methods

- (void) updateListenerOrientation {
  float yawRad = _listenerYaw * M_PI / 180.0;
  float pitchRad = _listenerPitch * M_PI / 180.0;
  float rollRad = _listenerRoll * M_PI / 180.0;
  
  float qW, qX, qY, qZ;
  leia_orientation_quaternion_convert(yawRad, pitchRad, rollRad, &qW, &qX, &qY, &qZ);
  leia_listener_orientation_update(_leiaEngine, qW, qX, qY, qZ);
}

@end

