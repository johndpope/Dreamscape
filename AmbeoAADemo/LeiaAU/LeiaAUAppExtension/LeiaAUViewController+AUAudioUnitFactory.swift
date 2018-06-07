/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// LeiaAUViewController is the app extension's principal class, responsible for creating both the audio unit and its view.

import CoreAudioKit
import LeiaAUFramework

extension LeiaAUViewController: AUAudioUnitFactory {

    /**
     * This implements the required 'AUAudioUnitFactory' protocol method.
     * When this view controller is instantiated in an extension process, it
     * creates its audio unit.
     */
    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        leiaAU = try LeiaAU(componentDescription: componentDescription, options: [])
        leiaAU?.leiaAUViewController = self
        return leiaAU!
    }

}
