/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

#ifndef LeiaAU_h
#define LeiaAU_h

#import <AudioToolbox/AudioToolbox.h>
#import <simd/simd.h>
#import <GLKit/GLKit.h>

@class LeiaAUViewController;

#define FourCCChars(CC) ((int)(CC)>>24)&0xff, ((int)(CC)>>16)&0xff, ((int)(CC)>>8)&0xff, (int)(CC)&0xff

@interface LeiaAU : AUAudioUnit

@property (weak) LeiaAUViewController* leiaAUViewController;

/** @return sample rate of LeiaAU */
+ (float) sampleRate;

/** @return frame count of LeiaAU */
+ (float) frameCount;

/**
 * Update the listener position with SceneKit coordinates.
 *
 * @param x  The X position.
 * @param y  The Y position.
 * @param z  The Z position.
 */
- (void) setLeiaAuListenerPosition: (float) x :(float) y :(float) z;

/**
 * Update the listener orientation with GLKQuaternion components.
 *
 * @param w  The new orientation, quaternion W element.
 * @param x  The new orientation, quaternion X element.
 * @param y  The new orientation, quaternion Y element.
 * @param z  The new orientation, quaternion Z element.
 */
- (void) setLeiaAuListenerOrientationQuaternion: (float) w :(float) x :(float) y :(float) z;

/**
 * Update the listener orientation with Euler angles (radians).
 *
 * @param yaw    The new orientation, yaw angle in radians
 * @param pitch  The new orientation, pitch angle in radians
 * @param roll   The new orientation, roll angle in radians
 */
- (void) setLeiaAuListenerOrientationEuler: (float) yaw :(float) pitch :(float) roll;

/**
 * Add a sound source to LeiaAU, with initial position in SceneKit coordinates
 *
 * @param sourceId A unique integer ID for the source.
 * @param x  The initial X position.
 * @param y  The initial Y position.
 * @param z  The initial Z position.
 */
- (void) addLeiaAuSource: (int) sourceId :(float) x :(float) y :(float) z;

/**
 * Remove a source from LeiaAU.
 *
 * @param source_id  An integer source identifier.
 */
- (void) removeLeiaAuSource: (int) source_id;

/**
 * @return the array mapping which source ID is at which input buffer index.
 */
- (NSArray *) getLeiaAuSourceIds;

/**
 * Update the position of a source with SceneKit coordinates.
 *
 * @param source_id  The integer identifier of the source.
 * @param x  The X position.
 * @param y  The Y position.
 * @param z  The Z position.
 */
- (void) setLeiaAuSourcePosition: (int) source_id :(float) x :(float) y :(float) z;

/**
 * The global minimum distance between listener and source to prevent high volumes / clipping.
 * This value overrides any global setting set during LeiaAU initialization.
 *
 * @param source_id  An integer source identifier.
 * @param min_distance The minimum distance in meters between listener and source at which the gain will be
 *                     limited when moving closer. This distance must be positive (> 0).
 */
- (void) setLeiaAuSourceMinimumDistanceGainLimit: (int) source_id :(float) min_distance;

/**
 * Set the RMS gain of latefield. Defaults to 1.0
 *
 * @param gain  Set the latefield gain. This is a simple multiplier.
 */
- (void) setLeiaAuLatefieldGain: (float) gain;

/**
 * Set the RMS gain of reflections. Defaults to 1.0
 *
 * @param gain  Set the reflection gain. This is a simple multiplier.
 */
- (void) setLeiaAuReflectionsGain: (float) gain;

/**
 * Set the current acoustic environment to be a Freefield.
 */
- (void) setLeiaAuEnvironmentFreefield;

/**
 * Set the current acoustic environment to be a Shoebox room.
 *
 * @param width   The width of the room in meters. A reasonable default is 10 meters.
 * @param length  The length of the room in meters. A reasonable default is 10 meters.
 * @param height  The height of the room in meters. A reasonable default is 10 meters.
 */
- (void) setLeiaAuEnvironmentShoebox: (float) width :(float) length :(float) height;

/**
 * Set the origin of the LeiaAU coordinate system, with respect
 * to the SceneKit coordinate system. The origin point is the
 * corner at the intersection of LEFT, BACK, and FLOOR surfaces.
 *
 * Note that, internally, Leia uses a right-handed coordinate system where the direction
 * of view is along the positive y-axis. This conversion is handled in the functions
 * scnToLeiaPosition() and scnToLeiaOrientation()
 */
- (void) setLeiaAuEnvironmentShoeboxOrigin: (float) x :(float) y :(float) z;

/**
 * Set the orientation of the LeiaAU coordinate system, with respect
 * to the SceneKit coordinate system.
 */
- (void) setLeiaAuEnvironmentShoeboxOrientationQuaternion: (float) w :(float) x :(float) y :(float) z;

/**
 * Set the orientation of the LeiaAU coordinate system in euler angles, with respect
 * to the SceneKit coordinate system.
 */
- (void) setLeiaAuEnvironmentShoeboxOrientationEuler: (float) yaw :(float) pitch :(float) roll;

/**
 * Update the dimensions of the current Shoebox environment model.
 * This function does nothing if the current environment is not a Shoebox.
 *
 * @param width   The width of the room in meters.
 * @param length  The length of the room in meters.
 * @param height  The height of the room in meters.
 */
- (void) setLeiaAuEnvironmentShoeboxDimensions: (float) width :(float) length :(float) height;

/**
 * Set the material on a Shoebox surface. This function does nothing if the current environment is not a Shoebox.
 *
 * @param surfaceId     The id of the surface as an enum.
 * @param materialId  The string name of the material to assign to the surface.
 */
- (void) setLeiaAuEnvironmentShoeboxReflectionMaterialForPath: (int) surfaceId : (NSString *) materialId;

@end

#endif /* LeiaAU_h */
