/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

#import "LeiaAU.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudioKit/AUViewController.h>
#import <GLKit/GLKit.h>

#import "LeiaAUFramework/LeiaAUFramework-Swift.h"
#import "SennheiserAmbeoLeia.h"

#include <string>

#pragma mark LeiaAU

static const LeiaSampleRate SAMPLE_RATE = SAMPLERATE_44100;
static const AUAudioFrameCount FRAME_COUNT = 512;
static const int MAX_NUM_SOURCES = 8; // set this to the maximum number of sources we expect in the host app
static const int MAX_NUM_SOURCE_CHANNELS = 1; // currently, LeiaAU supports only independent mono sources

#pragma mark - LeiaAU : AUAudioUnit

@interface LeiaAU ()
    @property AUAudioUnitBus *outputBus;
    @property AUAudioUnitBusArray *inputBusArray;
    @property AUAudioUnitBusArray *outputBusArray;
    @property AUAudioChannelCount channelCountInput;
    @property AUAudioChannelCount channelCountOutput;
    @property LeiaInstance *leiaEngine;
    @property NSMutableArray *leiaSourceIds;
@end

#pragma mark BufferedAudioBus Utility Class

/**
 * Utility struct to manage audio formats and buffers
 * for LeiaAU's input audio busses.
 */
struct BufferedAudioBus {

    AUAudioUnitBus* bus = nullptr;
    AUAudioFrameCount maxFrames = 0;
    AVAudioPCMBuffer* pcmBuffer = nullptr;
    AudioBufferList const* originalAudioBufferList = nullptr;
    AudioBufferList* mutableAudioBufferList = nullptr;

    void init(AVAudioFormat* defaultFormat, AVAudioChannelCount maxChannels) {
        maxFrames = 0;
        pcmBuffer = nullptr;
        originalAudioBufferList = nullptr;
        mutableAudioBufferList = nullptr;
        bus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormat error:nil];
        bus.maximumChannelCount = maxChannels;
    }

    void allocateRenderResources(AUAudioFrameCount inMaxFrames) {
        maxFrames = inMaxFrames;
        pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:bus.format frameCapacity: maxFrames];
        originalAudioBufferList = pcmBuffer.audioBufferList;
        mutableAudioBufferList = pcmBuffer.mutableAudioBufferList;
    }

    void deallocateRenderResources() {
        pcmBuffer = nullptr;
        originalAudioBufferList = nullptr;
        mutableAudioBufferList = nullptr;
    }
};

#pragma mark - BufferedInputBus: BufferedAudioBus

/**
 * BufferedInputBus is a struct that manages a buffer into
 * which LeiaAU's input busses can pull their input data.
 */
struct BufferedInputBus : BufferedAudioBus {

    /**
     * Gets input data for this input by preparing the
     * input buffer list and pulling the pullInputBlock.
     */
    AUAudioUnitStatus pullInput(AudioUnitRenderActionFlags *actionFlags,
                                AudioTimeStamp const* timestamp,
                                AVAudioFrameCount frameCount,
                                NSInteger inputBusNumber,
                                AURenderPullInputBlock pullInputBlock) {
        if (pullInputBlock == nullptr) { return kAudioUnitErr_NoConnection; }
        // Note: LeiaAU must supply valid buffers in (inputData->mBuffers[x].mData) and mDataByteSize.
        // mDataByteSize must be consistent with frameCount.
        // The AURenderPullInputBlock may provide input in those specified buffers, or it may replace
        // the mData pointers with pointers to memory which it owns and guarantees will remain valid
        // until the next render cycle.
        prepareInputBufferList();
        return pullInputBlock(actionFlags, timestamp, frameCount, inputBusNumber, mutableAudioBufferList);
    }

    /**
     * Populates the mutableAudioBufferList with the data pointers from
     * the originalAudioBufferList. The upstream audio unit may overwrite
     * these with its own pointers, so each render cycle this function needs
     * to be called to reset them.
     */
    void prepareInputBufferList() {
        UInt32 byteSize = maxFrames * sizeof(float);
        mutableAudioBufferList->mNumberBuffers = originalAudioBufferList->mNumberBuffers;
        for (UInt32 i = 0; i < originalAudioBufferList->mNumberBuffers; ++i) {
            mutableAudioBufferList->mBuffers[i].mNumberChannels = originalAudioBufferList->mBuffers[i].mNumberChannels;
            mutableAudioBufferList->mBuffers[i].mData = originalAudioBufferList->mBuffers[i].mData;
            mutableAudioBufferList->mBuffers[i].mDataByteSize = byteSize;
        }
    }
};

@implementation LeiaAU {
    // C++ members need to be ivars; they would be copied on access if they were properties.
    BufferedInputBus bufferedInputBusses[MAX_NUM_SOURCES];
}

+ (float) sampleRate {
    return SAMPLE_RATE;
}

+ (float) frameCount {
    return FRAME_COUNT;
}

/**
 * Initialize the audio unit with the provided AudioComponentDescription of LeiaAU
 */
- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {

    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) { return nil; }

    printf("LeiaAU - AUAudioUnit initWithComponentDescription:\n");
    printf("         componentType: %c%c%c%c\n", FourCCChars(componentDescription.componentType));
    printf("         componentSubType: %c%c%c%c\n", FourCCChars(componentDescription.componentSubType));
    printf("         componentManufacturer: %c%c%c%c\n", FourCCChars(componentDescription.componentManufacturer));
    printf("         componentFlags: %#010x\n", componentDescription.componentFlags);
    printf("LeiaAU - Process Name %s PID %d\n", [[[NSProcessInfo processInfo] processName] UTF8String], [[NSProcessInfo processInfo] processIdentifier]);

    // Initialize a default format for the busses.
    // Input busses have 1 channel (currently LeiaAU only supports mono inputs for sources).
    // The output bus has 2 channels (binaural stereo).
    AVAudioFormat *defaultFormatInput = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:SAMPLE_RATE channels:MAX_NUM_SOURCE_CHANNELS];
    AVAudioFormat *defaultFormatOutput = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:SAMPLE_RATE channels:2]; // binaural stereo

    // Initialize the input busses and output bus.
    for (int bus = 0; bus < MAX_NUM_SOURCES; bus++) {
        bufferedInputBusses[bus].init(defaultFormatInput, MAX_NUM_SOURCE_CHANNELS);
    }
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:defaultFormatOutput error:nil];
    self.maximumFramesToRender = FRAME_COUNT;
    
    // Ensure that busses were successfully initialized
    if (self.outputBus.format.channelCount != 2 || bufferedInputBusses[0].bus.format.channelCount < 1) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:kAudioUnitErr_FailedInitialization userInfo:nil];
        }
        self.renderResourcesAllocated = NO;
        return nil;
    }
    self.channelCountInput = bufferedInputBusses[0].bus.format.channelCount;
    self.channelCountOutput = self.outputBus.format.channelCount;

    // Create the input and output bus arrays.
    // The number of available input busses must be predefined with MAX_NUM_SOURCES.
    // There is only one output bus in the output bus array.
    NSArray *audioUnitInputBusses = [NSArray array];
    for (int bus = 0; bus < MAX_NUM_SOURCES; bus++) {
      audioUnitInputBusses = [audioUnitInputBusses arrayByAddingObject:bufferedInputBusses[bus].bus];
    }
    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeInput busses:audioUnitInputBusses];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self busType:AUAudioUnitBusTypeOutput busses: @[_outputBus]];

    // Attempt to create Leia engine instance
    self.leiaEngine = leia_new(SAMPLE_RATE, FRAME_COUNT);
    printf("LeiaAU - Leia engine instance created with sample rate %.0u, preferred frame count %d,", SAMPLE_RATE, FRAME_COUNT);
    printf(" and %lu input busses available.\n", (unsigned long)_inputBusArray.count);
    
    // Create array of LeiaSource IDs
    self.leiaSourceIds = [NSMutableArray array];

    return self;
}

-(void)dealloc {
    // Delete the Leia engine instance
    leia_delete(self.leiaEngine);
}

#pragma mark - AUAudioUnit (Overrides)

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

/**
 * Allocate resources required to render LeiaAU. The host app
 * must call this to initialize LeiaAU before beginning to render.
 */
- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) { return NO; }

    for (int bus = 0; bus < MAX_NUM_SOURCES; bus++) {
        bufferedInputBusses[bus].allocateRenderResources(self.maximumFramesToRender);
    }
    return YES;
}

/**
 * Deallocate resources allocated by allocateRenderResourcesAndReturnError:
 * Hosts should call this after finishing rendering.
 */
- (void)deallocateRenderResources {
    for (int bus = 0; bus < MAX_NUM_SOURCES; bus++) {
        bufferedInputBusses[bus].deallocateRenderResources();
    }
    [super deallocateRenderResources];
}

#pragma mark- AUAudioUnit (Optional Properties)

/** The Leia engine, and thus the audio unit, cannot process in place. */
- (BOOL)canProcessInPlace {
    return NO;
}

#pragma mark - AUAudioUnit (AUAudioUnitImplementation)

/**
 * AUInternalRenderBlock, i.e. the LeiaAU audio processing callback.
 */
- (AUInternalRenderBlock)internalRenderBlock {
    __block BufferedInputBus *inputBusses = bufferedInputBusses;
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {

        if (frameCount < FRAME_COUNT) {
            printf("LeiaAU - WARNING: frame count %d is less than preferred FRAME_COUNT %d\n", frameCount, FRAME_COUNT);
        } else if (frameCount > FRAME_COUNT) {
            printf("LeiaAU - ERROR: frame count %d is more than preferred FRAME_COUNT %d\n", frameCount, FRAME_COUNT);
        }

        // Prepare input buffers
        const int kNumInputs = (int) [self.leiaSourceIds count];
        for (int i = 0; i < kNumInputs; ++i) {
          AudioUnitRenderActionFlags kPullFlags = 0;
          AUAudioUnitStatus err = inputBusses[i].pullInput(&kPullFlags, timestamp, frameCount, i, pullInputBlock);
          assert(err == 0 && "Error while pulling data from input buffers.");
          leia_source_audio_update(self.leiaEngine, (int)[self.leiaSourceIds[i] integerValue],
                                   (float *) inputBusses[i].mutableAudioBufferList->mBuffers[0].mData,
                                   (int) frameCount);
        }

        // Prepare output buffers
        float *outBuffers[2] = {
            (float *) outputData->mBuffers[0].mData,
            (float *) outputData->mBuffers[1].mData
        };

        // Process Leia
        leia_process_source_audio(self.leiaEngine, outBuffers, (int) frameCount);

        return noErr;
    };
}

#pragma mark - AUAudioUnit ViewController related

- (NSIndexSet *)supportedViewConfigurations:(NSArray<AUAudioUnitViewConfiguration *> *)availableViewConfigurations {
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    for (unsigned i = 0; i < [availableViewConfigurations count]; ++i) {
        // The two views we actually have
        if ((availableViewConfigurations[i].width >= 800 && availableViewConfigurations[i].height >= 500) ||
            (availableViewConfigurations[i].width <= 400 && availableViewConfigurations[i].height <= 100) ||
            // Full-screen size or our own window, always supported, we return our biggest view size in this case
            (availableViewConfigurations[i].width == 0 && availableViewConfigurations[i].height == 0)) {
            [result addIndex:i];
        }
    }
    return result;
}

- (void) selectViewConfiguration:(AUAudioUnitViewConfiguration *)viewConfiguration {
  return [self.leiaAUViewController handleSelectViewConfiguration:viewConfiguration];
}

/*******************************************************************************************/

#pragma mark - Leia engine interface

/** Set the LeiaListener position. */
- (void) setLeiaAuListenerPosition: (float) x :(float) y :(float) z {
    [self.leiaAUViewController updateListenerPositionWithX:x y:y z:z];
    [self scnToLeiaPosition:(&x):(&y):(&z)];
    leia_listener_position_update(self.leiaEngine, x, y, z);
}

/** Set the LeiaListener orientation with Quaternion. */
- (void) setLeiaAuListenerOrientationQuaternion: (float) w :(float) x :(float) y :(float) z {
    [self.leiaAUViewController updateListenerOrientationWithW:w x:x y:y z:z];
    [self scnToLeiaOrientation: &w :&x :&y : &z];
    leia_listener_orientation_update(self.leiaEngine, w, x, y, z);
}

/** Update the listener orientation with Euler angles (radians) */
- (void) setLeiaAuListenerOrientationEuler: (float) yaw :(float) pitch :(float) roll {
    [self arkitToLeiaEuler:(&yaw) :(&pitch) :(&roll)];
    float w, x, y, z;
    leia_orientation_quaternion_convert(yaw, pitch, roll, &w, &x, &y, &z);
    [self.leiaAUViewController updateListenerOrientationWithW:w x:x y:y z:z];
    leia_listener_orientation_update(self.leiaEngine, w, x, y, z);
}

/** Add a LeiaSource to the Leia system. */
- (void) addLeiaAuSource: (int) sourceId :(float) x :(float) y :(float) z {
    simd_float3 scn = simd_make_float3(x, y, z);
    [self scnToLeiaPosition:(&x):(&y):(&z)];
    leia_source_add(self.leiaEngine, sourceId, x, y, z);
    [self.leiaSourceIds addObject:[NSNumber numberWithInt:sourceId]];
    printf("LeiaAU - LeiaSource with ID %d added.\n", sourceId);
    [self.leiaAUViewController numSourcesChanged];
    [self.leiaAUViewController updateSourcePositionWithId:sourceId x:scn[0] y:scn[1] z:scn[2]];
}

/** Remove a LeiaSource with the given ID from the Leia system */
- (void) removeLeiaAuSource: (int) sourceId {
    [self.leiaSourceIds removeObject:[NSNumber numberWithInt:sourceId]];
    leia_source_remove(self.leiaEngine, sourceId);
    [self.leiaAUViewController numSourcesChanged];
    printf("LeiaAU - LeiaSource with ID %d removed.\n", sourceId);
}

/** Get the array of LeiaSource IDs. */
- (NSArray *) getLeiaAuSourceIds {
    return self.leiaSourceIds;
}

/** Set the position of the LeiaSource with the given ID */
- (void) setLeiaAuSourcePosition: (int) sourceId :(float) x :(float) y :(float) z {
    [self.leiaAUViewController updateSourcePositionWithId:sourceId x:x y:y z:z];
    [self scnToLeiaPosition:(&x):(&y):(&z)];
    leia_source_position_update(self.leiaEngine, sourceId, x, y, z);
}

/** Set the global minimum distance between listener and source to prevent high volumes / clipping */
- (void) setLeiaAuSourceMinimumDistanceGainLimit: (int) sourceId :(float) min_distance {
    leia_source_minimum_distance_gain_limit_set(self.leiaEngine, sourceId, min_distance);
}

/** Set the gain of the latefield (linear scale) */
- (void) setLeiaAuLatefieldGain: (float) gain {
    leia_gain_latefield_set(self.leiaEngine, gain);
}

/** Set the gain of the reflections (linear scale) */
- (void) setLeiaAuReflectionsGain: (float) gain {
    leia_gain_reflections_set(self.leiaEngine, gain);
}

/** Set the current acoustic environment to be a Freefield */
- (void) setLeiaAuEnvironmentFreefield {
    leia_environment_freefield_set(self.leiaEngine);
    [[self.leiaAUViewController environmentSegmentedControl] setSelectedSegmentIndex:0];
}

/** Set the current acoustic environment to be a Shoebox room */
- (void) setLeiaAuEnvironmentShoebox: (float) width :(float) length :(float) height {
    [self fmaxDimensions:(&width):(&length):(&height):0.01];
    leia_environment_shoebox_set(self.leiaEngine, width, length, height);
    leia_gain_latefield_set(self.leiaEngine, 2.0); // default to +6 db Gain
    [[self.leiaAUViewController environmentSegmentedControl] setSelectedSegmentIndex:1];
}

/** Set the current Shoebox room's dimensions */
- (void) setLeiaAuEnvironmentShoeboxDimensions: (float) width :(float) length :(float) height {
    [self fmaxDimensions:(&width):(&length):(&height):0.01];
    leia_environment_shoebox_dimensions_update(self.leiaEngine, width, length, height);
}

/** Set the material on a Shoebox surface */
- (void) setLeiaAuEnvironmentShoeboxReflectionMaterialForPath: (int) surfaceId : (NSString *) materialId {
    const char *cString = [materialId cStringUsingEncoding:NSASCIIStringEncoding];
    leia_environment_shoebox_material_update(self.leiaEngine, (LeiaSurfaceID) surfaceId, cString);
}

/** Set the origin of the Shoebox (corner at the intersection of LEFT, BACK, and FLOOR surfaces) */
- (void) setLeiaAuEnvironmentShoeboxOrigin: (float) x :(float) y :(float) z {
    [self scnToLeiaPosition:(&x):(&y):(&z)];
    leia_environment_origin_update(self.leiaEngine, x, y, z);
}

/** Set the orientation of the Shoebox with quaternion */
- (void) setLeiaAuEnvironmentShoeboxOrientationQuaternion: (float) w :(float) x :(float) y :(float) z {
    [self scnToLeiaOrientation:(&w):(&x):(&y):(&z)];
    leia_environment_orientation_update(self.leiaEngine, w, x, y, z);
}

/** Set the orientation of the Shoebox with euler angles */
- (void) setLeiaAuEnvironmentShoeboxOrientationEuler: (float) yaw :(float) pitch :(float) roll {
    [self arkitToLeiaEuler:(&yaw) :(&pitch) :(&roll)];
    float w, x, y, z;
    leia_orientation_quaternion_convert(yaw, pitch, roll, &w, &x, &y, &z);
    leia_environment_orientation_update(self.leiaEngine, w, x, y, z);
}

/*******************************************************************************************/

#pragma mark - Leia engine helper methods

/**
 * Converts an ARKit Euler angle to its
 * corresponding Leia internal Euler angle
 */
- (void) arkitToLeiaEuler: (float *) yaw :(float *) pitch :(float *) roll {
    // In ARKit, only the `roll` element has a different sign.
    *roll = -*roll;
}

/**
 * Converts a SceneKit orientation quaternion to its
 * corresponding Leia internal orientation quaternion.
 */
- (void) scnToLeiaOrientation: (float *) w :(float *) x :(float *) y :(float *) z {
    float scnW = *w;
    float scnX = *x;
    float scnY = *y;
    float scnZ = *z;
    *w = scnW;
    *x = scnX;
    *y = -scnZ;
    *z = scnY;
}

/**
 * Converts a SceneKit coordinate point to its corresponding
 * Leia internal coordinate system point.
 */
- (void) scnToLeiaPosition: (float *) x :(float *) y :(float *) z {
    float scnX = *x;
    float scnY = *y;
    float scnZ = *z;
    *x = scnX;
    *y = -scnZ;
    *z = scnY;
}

/**
 * Ensures that the values of the given dimensions
 * are each greater than or equal to `min`.
 */
- (void) fmaxDimensions: (float *) width :(float *) length :(float *) height :(float) min {
    *width =  fmax(*width,  min);
    *length = fmax(*length, min);
    *height = fmax(*height, min);
}

@end
