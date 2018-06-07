/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

#import <AudioToolbox/AudioToolbox.h>

// Define parameter addresses.
extern const AUParameterAddress paramIDLeiaListenerYaw;
extern const AUParameterAddress paramIDLeiaListenerPitch;
extern const AUParameterAddress paramIDLeiaListenerRoll;

@interface LeiaAudioUnit : AUAudioUnit

@end
