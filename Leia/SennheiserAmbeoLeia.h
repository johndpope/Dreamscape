/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

#ifndef _SENHEISER_AMBEO_LEIA_H_
#define _SENHEISER_AMBEO_LEIA_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void LeiaInstance;
  
/** An enumerator for the surfaces where reflections occur. */
typedef enum {
  SURFACE_DIRECT = 0,
  SURFACE_LEFT,
  SURFACE_FRONT,
  SURFACE_RIGHT,
  SURFACE_BACK,
  SURFACE_CEILING,
  SURFACE_FLOOR
} LeiaSurfaceID;

typedef enum {
  SAMPLERATE_44100 = 44100,
  SAMPLERATE_48000 = 48000,
  SAMPLERATE_88200 = 88200,
  SAMPLERATE_96000 = 96000,
  SAMPLERATE_192000 = 192000
} LeiaSampleRate;

// MARK: - Constructor / Decstructor

/**
 * Create a new instance of Leia.
 * A default freefield environment is created which computes only direct paths, and no reflections or latefield.
 *
 * @param sampleRate  The sample rate at which Leia will run.
 * @param maxBlockSize  The maximum frame size which will be requested from Leia. Smaller frame sizes are allowed.
 *
 * @return  A new instance of Leia.
 */
LeiaInstance* leia_new(LeiaSampleRate sampleRate, int maxBlockSize);
  
/**
 * Destroy an instance of Leia.
 *
 * @param leia  A Leia instance.
 */
void leia_delete(LeiaInstance* leia);

// MARK: - Audio functions
  
/**
 * Processes the supplied audio buffers and writes the result to output buffers (out-of-place).
 * A source id array is used to indicate the source order in the input buffer.
 *
 * @note When this function is called, pending parameter changes are applied before processing the block of audio.
 *
 * @param sourceIndexArray  A mapping indicating which source id is at which input buffer index.
 *                          Must be of length num_sources.
 * @param inputBuffers  The input buffers as an array of arrays e.g. [[0000][1111][2222][...]]
 *                      Dimensions must be {num_sources, n}
 * @param outputBuffers  The output buffers as an array of arrays e.g. [[LLLL][RRRR]].
 *                       The output buffers must represent two channels. Dimensions must be {2, n}
 * @param n  The number of samples to process - must be <= maxBlockSize.
 */
void leia_process(LeiaInstance* leia, const int* sourceIndexArray,
                  const float** inputBuffers, float** outputBuffers, int n);

/**
 * An alternate audio processing function that uses pre-assigned audio buffers for each source
 * by calling leia_source_audio_update() beforehand.
 *
 * @note When this function is called, pending parameter changes are applied before processing the block of audio.
 *
 * @param leia  A Leia instance.
 * @param outputBuffers  The output buffers as an array of arrays e.g. [[LLLL][RRRR]].
 *                       The output buffers must represent two channels. Dimensions must be {2, n}
 * @param n  The number of samples to process - must be <= maxBlockSize.
 */
void leia_process_source_audio(LeiaInstance* leia, float** outputBuffers, int n);


// MARK: - Source functions
  
/**
 * Add a source to the spatialiser. Orientation as quaternions.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  A user supplied unique id for this source.
 * @param pX  The initial X position of the source in meters. +X points to the right
 * @param pY  The initial Y position of the source in meters. +Y points ahead.
 * @param pZ  The initial Z position of the source in meters. +Z points upwards.
 */
void leia_source_add(LeiaInstance* leia, int sourceId, float pX, float pY, float pZ);
  
/**
 * Remove a source.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  An integer source identifier.
 */
void leia_source_remove(LeiaInstance* leia, int sourceId);

/**
 * Update the audio of a source.
 *
 * @param leia  A Leia instance.
 * @param sourceId  The integer identifier of the source.
 * @param buffer  A buffer of sample data.
 * @param n  The length of the buffer in samples.
 */
void leia_source_audio_update(LeiaInstance* leia, int sourceId, float* buffer, int n);
  
/**
 * Update the position of a source.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  The integer identifier of the source.
 * @param pX  The new X position of the source.
 * @param pY  The new Y position of the source.
 * @param pZ  The new Z position of the source.
 */
void leia_source_position_update(LeiaInstance* leia, int sourceId, float pX, float pY, float pZ);


// MARK: - Listener functions
  
/**
 * Update the listener position.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param pX  The new X position of the listener in meters.
 * @param pY  The new Y position of the listener in meters.
 * @param pZ  The new Z position of the listener in meters.
 */
void leia_listener_position_update(LeiaInstance* leia, float pX, float pY, float pZ);

/**
 * Update the listener orientation.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param qW  The new orientation of the listener, Quaternion W element.
 * @param qX  The new orientation of the listener, Quaternion X element.
 * @param qY  The new orientation of the listener, Quaternion Y element.
 * @param qZ  The new orientation of the listener, Quaternion Z element.
 */
void leia_listener_orientation_update(LeiaInstance* leia, float qW, float qX, float qY, float qZ);
  

// MARK: - Parameter functions
  
/**
 * The source minimum distance between listener and source to prevent high volumes / clipping. This value overrides
 * any global setting set in the constructor.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  An integer source identifier.
 * @param minDistance  The minimum distance in meters between listener and source at which the gain will be
 *                     limited when moving closer. This distance must be positive (> 0).
 */
void leia_source_minimum_distance_gain_limit_set(LeiaInstance* leia, int sourceId, float minDistance);

/**
 * Same as leia_source_minimum_distance_gain_limit_set(), but applied to all sources.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param minDistance  The minimum distance in meters between listener and source at which the gain will be
 *                     limited when moving closer. This distance must be positive (> 0).
 */
void leia_global_minimum_distance_gain_limit_set(LeiaInstance* leia, float minDistance);
  
/**
 * The distance attenuation factor. A factor of one will have a physically correct attenuation with 1/distance.
 * A setting > 1.0f will have a more drastic attenuation, a settings < 1.0f will have less drastic attenuation.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  An integer source identifier.
 * @param factor  The attenuation factor.
 */
void leia_source_distance_attenuation_factor_set(LeiaInstance* leia, int sourceId, float factor);
  
/**
 * Same as leia_source_distance_attenuation_factor_set(), but applied to all sources.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param factor  The attenuation factor.
 */
void leia_global_distance_attenuation_factor_set(LeiaInstance* leia, float factor);

/**
 * Contrary to real physics, it might not be a desired effect introduce additional delay to the direct path.
 * Turning on zero delay mode will effectively turn of the doppler effect on the direct path. This function
 * sets the setting per source.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  An integer source identifier.
 * @param zeroDelayEnabled  True if all signal delays should be relative to the shortest one. False otherwise.
 */
void leia_source_zerodelay_set(LeiaInstance* leia, int sourceId, bool zeroDelayEnabled);
  
/**
 * Same as leia_source_zerodelay_set(), but applied to all sources.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param zeroDelayEnabled  True if all signal delays should be relative to the shortest one. False otherwise.
 */
void leia_global_zerodelay_set(LeiaInstance* leia, bool zeroDelayEnabled);

/**
 * Set the clarity value for a single source. Does not effect the reflections of that source.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param sourceId  The source id.
 * @param clarity  A value between 0 (maximum externalisation, original HRTF) and 1 (full clarity).
 */
void leia_source_clarity_set(LeiaInstance* leia, int sourceId, float clarity);
  
/**
 * Set the global clarity value.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param clarity  A value between 0 (maximum externalisation, original HRTF) and 1 (full clarity).
 */
void leia_global_clarity_set(LeiaInstance* leia, float clarity);

// MARK: - Environment functions
  
/**
 * Set the current environment to be a Freefield.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 */
void leia_environment_freefield_set(LeiaInstance* leia);

/**
 * Set the current environment to be a Shoebox.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param width  The width of the room in meters. A reasonable default is 10 meters.
 * @param length  The length of the room in meters. A reasonable default is 10 meters.
 * @param height  The height of the room in meters. A reasonable default is 10 meters.
 */
void leia_environment_shoebox_set(LeiaInstance* leia, float width, float length, float height);

/**
 * Update the dimensions of the current Shoebox environment model. This function does nothing if the current
 * environment is not a Shoebox.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param width  The width of the room in meters.
 * @param length  The length of the room in meters.
 * @param height  The height of the room in meters.
 */
void leia_environment_shoebox_dimensions_update(LeiaInstance* leia, float width, float length, float height);

/**
 * Set the material on a Shoebox surface. This function does nothing if the current environment is not a Shoebox.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param surface_id  The id of the surface as an enum.
 * @param name  The string name of the material to assign to the surface.
 */
void leia_environment_shoebox_material_update(LeiaInstance* leia, LeiaSurfaceID surface_id, const char* name);
  
/**
 * Set the origin of the environment. This is most useful with the shoebox environment. The origin is defined to
 * be in the bottom back left corner of the shoebox. That means if if the position or orientation of the environment
 * hasn't been updated, all positive coordinates that are less than the respective width, length and height fall within
 * the shoebox.
 *
 * @param leia  A Leia instance.
 * @param pX  The updated x position of the environment
 * @param pY  The updated y position of the environment
 * @param pZ  The updated z position of the environment
 *
 */
void leia_environment_origin_update(LeiaInstance* leia, float pX, float pY, float pZ);
  
/**
 * Set the orientation of the environment. This is most useful with the shoebox environment.
 *
 * @param leia  A Leia instance.
 * @param qW  Quaternion w element.
 * @param qX  Quaternion x element.
 * @param qY  Quaternion y element.
 * @param qZ  Quaternion z element.
 *
 */
void leia_environment_orientation_update(LeiaInstance* leia, float qW, float qX, float qY, float qZ);
  
// MARK: - Utility functions

/**
 * Get the current samplerate value.
 *
 * @param leia  A Leia instance.
 *
 * @return  The current samplerate value as an enum.
 */
LeiaSampleRate leia_samplerate_get(LeiaInstance* leia);

/**
 * Get the maximum configured block size.
 *
 * @param leia  A Leia instance.
 *
 * @return  Get the maximum configured block size.
 */
int leia_max_blocksize_get(LeiaInstance* leia);

/**
 * Set the RMS gain of latefield. Defaults to one.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param gain  Set the latefield gain. This is a simple multiplier.
 */
void leia_gain_latefield_set(LeiaInstance* leia, float gain);

/**
 * Returns the current latefield gain.
 *
 * @param leia  A Leia instance.
 *
 * @return  The latefield gain.
 */
float leia_gain_latefield_get(LeiaInstance* leia);

/**
 * Set the RMS gain of reflections. Defaults to one.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param leia  A Leia instance.
 * @param gain  Set the reflection gain. This is a simple multiplier.
 */
void leia_gain_reflections_set(LeiaInstance* leia, float gain);

/**
 * Returns the current reflections gain.
 *
 * @param leia  A Leia instance.
 *
 * @return  The reflections gain.
 */
float leia_gain_reflections_get(LeiaInstance* leia);

/**
 * Apply all pending parameter changes. This is automatically done each time the process function is called, but this
 * function allows to apply parameters without processing audio, which might be useful or necessary in some applications.
 *
 * @param leia  A Leia instance.
 */
void leia_preprocess(LeiaInstance* leia);

  
// MARK: - Static utility functions (no Leia instance required)

/**
 * A convenience function to interleave the split-channel output of Leia to a single stereo
 * interleaved buffer.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param inputBuffer  A split stereo buffer i.e. [[LLLL][RRRR]]
 * @param outputBuffer An interleaved stereo buffer i.e. [LRLRLRLR]
 * @param n  The length in frames of the input buffer.
 */
void leia_stereo_interleave(float** inputBuffer, float* outputBuffer, int n);

/**
 * A convenience function to uninterleave a single stereo interleaved buffer to a split-channel format.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param inputBuffer  An interleaved stereo buffer i.e. [LRLRLRLR]
 * @param outputBuffer  A split stereo buffer i.e. [[LLLL][RRRR]]
 * @param n  The length in frames of the input buffer.
 */
void leia_stereo_uninterleave(float* inputBuffer, float** outputBuffer, int n);

/**
 * Converts a Cartesian position into the spherical coordinates {azimuth, elevation, radius}.
 * These coordinates are defined in the Leia Coordinate System.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param [in]  pX  The X position
 * @param [in]  pY  The Y position
 * @param [in]  pZ  The Z position
 * @param [out]  azimuth  the angle (in radians) on the XY plane, measured CCW from the front/north (positive Y)
 *                        range is defined as [0, 2*PI[
 * @param [out]  elevation  the angle (in radians) between the XY plane and Z axis, with +90° at the Zenith (positive Z)
 *                          range is defined a [-PI/2, PI/2]
 * @param [out]  radius  measured in meters from the origin
 */
void leia_position_spherical_convert(float pX, float pY, float pZ, float* azimuth, float* elevation, float* radius);

/**
 * Converts spherical coordinates into a Cartesian position {x, y, z}
 * These coordinates are defined in the Leia Coordinate System.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param [in]  azimuth  the angle (in radians) on the XY plane, measured CCW from the front/north (positive Y)
 *                       range is defined as [0, 2*PI[
 * @param [in]  elevation  the angle (in radians) between the XY plane and Z axis, with +90° at the Zenith (positive Z)
 *                         range is defined a [-PI/2, PI/2]
 * @param [in]  radius  measured in meters from the origin
 * @param [out]  pX  The X position
 * @param [out]  pY  The Y position
 * @param [out]  pZ  The Z position
 */
void leia_position_cartesian_convert(float azimuth, float elevation, float radius, float* pX, float* pY, float* pZ);
  
/**
 * Converts a Quarternion orientation into the Euler Angles {yaw, pitch, roll}.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param qW [in]  Quaternion W element.
 * @param qX [in]  Quaternion X element.
 * @param qY [in]  Quaternion Y element.
 * @param qZ [in]  Quaternion Z element.
 * @param yaw [out]   Yaw Euler angle in radians.
 * @param pitch [out] Pitch Euler angle in radians.
 * @param roll [out]  Roll Euler angle in radians.
 */
void leia_orientation_euler_convert(float qW, float qX, float qY, float qZ, float* yaw, float* pitch, float* roll);

/**
 * Converts an orientation in Euler Angles in radians into a Quarternion orientation.
 *
 * THIS FUNCTION IS THREAD SAFE.
 *
 * @param yaw [in]   Yaw Euler angle in radians.
 * @param pitch [in] Pitch Euler angle in radians.
 * @param roll [in]  Roll Euler angle in radians.
 * @param qW [out]  Quaternion W element.
 * @param qX [out]  Quaternion X element.
 * @param qY [out]  Quaternion Y element.
 * @param qZ [out]  Quaternion Z element.
 */
void leia_orientation_quaternion_convert(float yaw, float pitch, float roll, float* qW, float* qX, float* qY, float* qZ);


#ifdef __cplusplus
}
#endif

#endif // _SENHEISER_AMBEO_LEIA_H_
