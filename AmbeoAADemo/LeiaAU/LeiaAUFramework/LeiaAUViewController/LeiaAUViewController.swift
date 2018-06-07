/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// View controller for the LeiaAU audio unit.

import UIKit
import CoreAudioKit

/// - Tag: LeiaAUViewController
@objc public class LeiaAUViewController: AUViewController,UITextFieldDelegate, UITableViewDelegate, UITableViewDataSource {

    // MARK: Properties
    
    @IBOutlet weak var objectTableView: UITableView!
    @IBOutlet weak var latefieldSlider: UISlider!
    @IBOutlet weak var latefieldTextField: UITextField!
    @IBOutlet weak var reflectionsSlider: UISlider!
    @IBOutlet weak var reflectionsTextField: UITextField!
    @IBOutlet weak var environmentSegmentedControl: UISegmentedControl!
    @IBOutlet var primaryView: UIView!

    /**
     * When this view controller is instantiated, its audio unit is created independently,
     * and passed to the view controller here.
     */
    public var leiaAU: LeiaAU? {
        didSet {
            /*
                We may be on a dispatch worker queue processing an XPC request at
                this time, and quite possibly the main queue is busy creating the
                view. To be thread-safe, dispatch onto the main queue.

             It's also possible that we are already on the main queue, so to
                protect against deadlock in that case, dispatch asynchronously.
             */
            DispatchQueue.main.async {
                if self.isViewLoaded {
                    self.connectViewWithAU()
                }
            }
        }
    }

    @objc public func handleSelectViewConfiguration(_ viewConfiguration: AUAudioUnitViewConfiguration) {
        // nothing to do here
    }

    // MARK: Tableview callbacks

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let numSources = leiaAU?.getSourceIds().count
        // Display all sources and listener
        return Int(numSources!) + 1
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "ObjectCell"
        let cell = objectTableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath) as? ObjectTableViewCell
        let sourceIds = leiaAU!.getSourceIds()
        if (indexPath.row == 0) {
            cell?.name.text = "Listener"
        } else {
          cell?.name.text = "Source ID: " + (sourceIds![indexPath.row - 1] as! NSNumber).stringValue
        }
        return cell!
    }

    @objc public func numSourcesChanged() {
        objectTableView.reloadData()
    }

    /**
     * Called after the view has loaded.
     *
     * Sets the LeiaAUViewController as the delegate for all table views
     * and text fields, and connects the UI to the LeiaAU Audio Unit status.
     */
    public override func viewDidLoad() {
        super.viewDidLoad()

        guard leiaAU != nil else { return }

        self.objectTableView.delegate = self
        self.objectTableView.dataSource = self
        self.latefieldTextField.delegate = self
        self.reflectionsTextField.delegate = self

        self.view.layer.borderColor = UIColor.black.cgColor
        self.view.layer.borderWidth = 2
        self.view.layer.cornerRadius = 1
        self.view.backgroundColor = UIColor.green

        connectViewWithAU()
    }
    
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }

    @objc public func updateListenerPosition(x: Float, y: Float, z: Float) {
        let cell = objectTableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? ObjectTableViewCell
        cell?.textFieldPositionX.text = String(x)
        cell?.textFieldPositionY.text = String(y)
        cell?.textFieldPositionZ.text = String(z)
    }

    @objc public func updateListenerOrientation(w: Float, x: Float, y: Float, z: Float) {
        let cell = objectTableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? ObjectTableViewCell
        cell?.textFieldOrientationW.text = String(w)
        cell?.textFieldOrientationX.text = String(x)
        cell?.textFieldOrientationY.text = String(y)
        cell?.textFieldOrientationZ.text = String(z)
    }

    @objc public func updateSourcePosition(id: Int, x: Float, y: Float, z: Float) {
        let sourceIds = leiaAU?.getSourceIds()
        let index = sourceIds!.index(where: {($0 as! NSNumber).intValue == id})
        let cell = objectTableView.cellForRow(at: IndexPath(row: index! + 1, section: 0)) as? ObjectTableViewCell
        cell?.textFieldPositionX.text = String(x)
        cell?.textFieldPositionY.text = String(y)
        cell?.textFieldPositionZ.text = String(z)
    }

    @IBAction func changedEnvironment(_ sender: AnyObject?) {
        guard sender === environmentSegmentedControl else { return }
        let value = environmentSegmentedControl.selectedSegmentIndex
        if (value == 0) { // selected Freefield
        } else { // selected Shoebox
        }
    }

    @IBAction func changedLatefieldSlider(_ sender: AnyObject?) {
        guard sender === latefieldSlider else { return }
        var value = latefieldSlider.value
        latefieldTextField.text = String(format: "%.1f", value)
        value = dbToGain(valueInDb: value)
        leiaAU?.setLeiaAuLatefieldGain(value)
    }

    @IBAction func changedLatefieldTextField(_ sender: Any) {
        var value = (latefieldTextField.text! as NSString).floatValue
        value = min(max(value, latefieldSlider.minimumValue), latefieldSlider.maximumValue)
        latefieldSlider.setValue(value, animated: true)
        latefieldTextField.text = String(format: "%.1f", value)
        value = dbToGain(valueInDb: value)
        leiaAU?.setLeiaAuLatefieldGain(value)
    }

    @IBAction func changedReflectionsSlider(_ sender: AnyObject?) {
        guard sender === reflectionsSlider else { return }
        var value = reflectionsSlider.value
        reflectionsTextField.text = String(format: "%.1f", value)
        value = dbToGain(valueInDb: value)
        leiaAU?.setLeiaAuReflectionsGain(value)
    }

    @IBAction func changedReflectionsTextField(_ sender: Any) {
        var value = (reflectionsTextField.text! as NSString).floatValue
        value = min(max(value, reflectionsSlider.minimumValue), reflectionsSlider.maximumValue)
        reflectionsSlider.setValue(value, animated: true)
        reflectionsTextField.text = String(format: "%.1f", value)
        value = dbToGain(valueInDb: value)
        leiaAU?.setLeiaAuReflectionsGain(value)
    }

    /**
     * We can't assume anything about whether the view or the AU is created first.
     * This gets called when either is being created and the other has already
     * been created.
     */
    func connectViewWithAU() {
        leiaAU?.leiaAUViewController = self
    }

    func dbToGain(valueInDb: Float) -> Float {
        return powf(10.0, (valueInDb / 20.0))
    }

    func gainToDb(gainValue: Float, minDb: Float) -> Float {
        let db = 20 * log10(gainValue)
        if db <= minDb {
            return 0.0
        } else  {
            return db
        }
    }
}
