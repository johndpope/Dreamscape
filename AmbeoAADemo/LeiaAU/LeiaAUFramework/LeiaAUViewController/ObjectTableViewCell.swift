/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

import UIKit

class ObjectTableViewCell: UITableViewCell {

    @IBOutlet public weak var name: UILabel!

    @IBOutlet weak var textFieldOrientationW: UITextField!
    @IBOutlet weak var textFieldOrientationX: UITextField!
    @IBOutlet weak var textFieldOrientationY: UITextField!
    @IBOutlet weak var textFieldOrientationZ: UITextField!

    @IBOutlet weak var textFieldPositionX: UITextField!
    @IBOutlet weak var textFieldPositionY: UITextField!
    @IBOutlet weak var textFieldPositionZ: UITextField!
}
