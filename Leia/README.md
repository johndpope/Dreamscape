<h1>Sennheiser AMBEO Leia</h1>
Leia is a binaural audio rendering engine, intended for gaming and VR/AR/MR applications, that models a freefield environment or a shoebox room with direct sound, early reflections, and latefield reverberation for an arbitrary number of audio sources.

- [Getting started](#getting-started)
  - [Distribution](#distribution)
  - [Leia coordinate system](#leia-coordinate-system)
    - [Position - dealing with spherical coordinates](#position-dealing-with-spherical-coordinates)
    - [Orientation - dealing with Euler angles](#orientation-dealing-with-euler-angles)
- [Using Leia](#using-leia)
  - [Basics](#basics)
  - [Position and orientation updates](#position-and-orientation-updates)
  - [Environment](#environment)
  - [Audio processing](#audio-processing)
  - [Fine-Tuning](#fine-tuning)

# Getting started
The following instructions will give you an introduction to Leia. To see how Leia is instantiated and used in an application context it's probably best to explore one of our demo projects.

## Distribution
Leia is distributed as a library with a C API: `libSennheiserAmbeoLeia.a` and the corresponding header file  `SennheiserAmbeoLeia.h`.

## Leia coordinate system
Leia uses a right-handed coordinate system, where the X-axis points to the right, the Y-axis to the front and the Z-axis upwards.
```
    z
    ^   y
    |  /
    | /
    |/
    +------> x

(Z, X, Y) --> (U, E, N)
```

### Position - dealing with spherical coordinates
Given the Leia coordinate system, the spherical coordinates are defined as follows:

* **Azimuth:** The angle on the XY plane, measured CCW from the front/north (positive Y) range is defined as [0°, 360°] or [0, 2π]
* **Elevation:** The angle between the XY plane and Z axis, with +90° at the Zenith (positive Z) range is defined as [-90°, 90°] or [-π/2, π/2]
* **Radius:** The distance in meters from the origin to the point.

### Orientation - dealing with Euler angles
While we natively use Quaternions in Leia to perform rotations associated with a certain orientation, many applications express orientation as Euler angles.

In the Leia coordinate system, the Euler angles are defined as follows:
* **Yaw**: rotation around the Z axis.
* **Pitch**: rotation around the X axis.
* **Roll**: rotation around the Y axis.

While there are several conventions of the order in which these Euler Angles are applied, we use an order of `yaw, pitch and roll`. These rotations are applied _intrinsically_ meaning the yaw rotation is applied to the (world) `Z` axis, the pitch rotation is applied to the newly-created X-axis (`X'`). Finally, roll is applied to the newly-created Y-axis (`Y"`).

Since we're in a right-handed coordinate system, all rotations are clockwise when you look in the direction of the axis.

# Using Leia

## Basics
To be able to process audio with Leia - in its simplest form - we need to perform the following steps:

1. Include the header in your source file `SennheiserAmbeoLeia.h`
1. Instantiate Leia with `leia_new()`
1. Add at least one source `leia_source_add()`
1. Call `leia_process()`

This is expressed in the following form in code:

First we allocate and initialize an instance of Leia. A pointer to this instance is returned and used as a handle for virtually every API call. The sample rate must be specified on construction. To use a different sample rate, delete and create a new Leia object. The maximum block size is the largest anticipated block size which will be used during the lifetime of the `LeiaInstance`.
```cpp
const int maxBlockSize = 1024;
LeiaInstance* leia = leia_new(SAMPLERATE_44100, maxBlockSize);
```

Now we add the source(s): You need give each source a unique ID (integer) to provide an initial position in meters (px, py, pz) in Cartesian coordinates. The source ID needs to be saved in your application - it has to be used to interact with the source in any way.

```cpp
const int sourceId1 = 0;
float px = 5.0f;
float py = 4.0f;
float pz = 3.0f;
leia_source_add(leia, sourceId1, px, py, pz);

const int sourceId2 = 1;
leia_source_add(leia, sourceId2, 0.5, 0.5, 0.5); // add a second source (direct)
```

Now we can process audio:
We assume `const float** inBuffers` points to our input buffers (dimensions: `{numSources, n}` and `float** outBuffers` points to our output buffers (dimensions: `{2, n}`. We always have 2 output channels.
```cpp
const int sourceIndexArray[2] = {sourceId1, sourceId2}; // specify the order of the sources in the input buffer
const int n = maxBlockSize; // we're choosing to processing the maximum, could be less

leia_process(leia, sourceIndexArray, inBuffers, outBuffers, n);
```

That's it - a block of samples for each channel has been written to `outBuffers`.

> **NOTE**: Do not forget to deallocate the instance with `leia_delete()` after using it (e.g. in your destructor).


## Position and orientation updates
The position and orientation of the listener and the position of the sources can be changed at any time after creation by calling one of these functions:
```cpp
leia_source_position_update(leia, sourceId, pX, pY, pZ);
leia_listener_position_update(leia, pX, pY, pZ);
leia_listener_orientation_update(leia, qW, qX, qY, qZ);
```

If you want to specify the orientation in Euler Angles rather than Quaternions, use the utility function (part of the API) to convert to Quaternions first and then use the same function:
```cpp
float yaw = 1.2f; 	// in radians
float pitch = 0.0f;
float roll = 0.9f;
float qW, qX, qY, qZ;
leia_orientation_quaternion_convert(yaw, pitch, roll, &qW, &qX, &qY, &qZ);
leia_listener_orientation_update(leia, qW, qX, qY, qZ);
```
> **NOTE**: The Quaternions used in the Leia API are defined so they are consistent with the Leia coordinate system. Directly feeding `SCNQuaternion` (Apple SceneKit) will not have the desired effects, since they are defined in a different coordinate system, the SceneKit coordinate system.

## Environment
There are currently two types of environments in Leia:
* Freefield -  no reflections nor latefield reverberation
* Shoebox Room - a cuboid with up to six reflections, latefield reverberation

The default environment in Leia is "freefield", which has no reflections nor latefield reverberation. If you want to activate the "shoebox" environment you need to provide a starting width, length and height in meters:

```cpp
leia_environment_shoebox_set(width, length, height);
```

You can configure the wall materials of the shoebox, which will apply specific filters to the signal when reflections occur.
```cpp
leia_environment_shoebox_material_update(leia, SURFACE_LEFT,    "heavy_velour");
leia_environment_shoebox_material_update(leia, SURFACE_FRONT,   "heavy_velour");
leia_environment_shoebox_material_update(leia, SURFACE_RIGHT,   "heavy_velour");
leia_environment_shoebox_material_update(leia, SURFACE_BACK,    "heavy_velour");
leia_environment_shoebox_material_update(leia, SURFACE_CEILING, "heavy_velour");
leia_environment_shoebox_material_update(leia, SURFACE_FLOOR,   "heavy_velour");
```
Here's a list of materials that come "built-in" into Leia:
- `"brick_unglazed"`
- `"carpet_heavy"`
- `"gypsum_board"`
- `"heavy_velour"`
- `"light_velour"`
- `"unchanged"` (full reflection, i.e. the reflection sounds the same as the original input)
- `"off"`  (full absorption, i.e. no reflections for this surface)

You can change the dimensions and position of the shoebox room in real-time by calling:
```cpp
leia_environment_shoebox_dimensions_update(leia, width, length, height);
```

You can also change origin and orientation of the shoebox room. Origin is always defined as the "bottom back left" corner of the room.
```cpp
leia_environment_origin_update(leia, x, y, z);
leia_environment_orientation_update(leia, w, x, y, z); // See above for using Euler angles.
```

## Audio processing
There are two possibilities for sending audio in and out of Leia.

### Direct approach
```cpp
leia_process(leia, sourceIndexArray, inBuffers, outBuffers, n);
```

This was used in the earlier, simple example. We assume `const float** inBuffers` points to our input buffers (dimensions: `{numSources, n}` and `float** outBuffers` points to our output buffers (dimensions: `{2, n}`. We always have 2 output channels.
The array `sourceIndexArray` describes which channel in the input_buffer corresponds to which source ID.

### Source audio approach
In this approach, the audio buffers are assigned individually to each source instead of bundling the buffers together.

First, assign the current audio buffer for each source by calling:
```cpp
leia_source_audio_update(leia, sourceId, inBuffer, n);
```
Then, call this function once to process the binaural output for all sources:
```cpp
leia_process_source_audio(leia, outBuffers, n);
```
Naturally, the number of samples `n` must match, and each source in Leia must be provided with a valid pointer to audio input data.

## Fine-Tuning
There are a couple of additional fine-tuning functions in the API that can be best explored by browsing through the header file directly and reading the comments.

These functions include:
- settings the RMS gain of reflections and latefield
- setting a clarity value per source or globally (clarity can reduce coloring artifacts for binaural audio)
- enabling zero-delay mode, which makes the transmission delay of a direct source path zero, and all associated reflection delays relative.
- setting a distance attenuation factor that describes how much attenuation is applied for a given distance to the source
- defining a minimum distance setting per source. This prevents overly loud levels when getting close to a source

All these parameters have been internally initialized to sensible default values, so the use of these fine-tuning functions is completely optional.
