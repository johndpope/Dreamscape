/**
 * Copyright (c) Sennheiser Electronic GmbH & Co. KG, 2018. All Rights Reserved.
 *
 * Distributed as part of the AMBEO Augmented Audio Developers Program.
 * You may only use this code under the terms stated in LICENSE.md, which was distributed alongside this code.
 */

// Popover view controller for choosing virtual materials to place in the AR scene.

import UIKit

// MARK: - MaterialCell

class MaterialCell: UITableViewCell {

    static let reuseIdentifier = "MaterialCell"

    @IBOutlet weak var materialTitleLabel: UILabel!
    @IBOutlet weak var materialImageView: UIImageView!

    var material: VirtualMaterial? {
        didSet {
            materialTitleLabel.text = material?.displayName
            materialImageView.image = material?.thumbImage
        }
    }
}

// MARK: - VirtualMaterialSelectionViewControllerDelegate

protocol VirtualMaterialSelectionViewControllerDelegate: class {
    func virtualMaterialSelectionViewController(_: VirtualMaterialSelectionViewController, didSelectMaterialAt index: Int)
    func virtualMaterialSelectionViewController(_: VirtualMaterialSelectionViewController, didDeselectMaterialAt index: Int)
}

class VirtualMaterialSelectionViewController: UITableViewController {

    private var selectedVirtualMaterialRows = IndexSet()
    weak var delegate: VirtualMaterialSelectionViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.separatorEffect = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .light))
    }

    override func viewWillLayoutSubviews() {
        preferredContentSize = CGSize(width: 250, height: tableView.contentSize.height)
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        // Check if the current row is already selected, then deselect it.
        if selectedVirtualMaterialRows.contains(indexPath.row) {
            delegate?.virtualMaterialSelectionViewController(self, didDeselectMaterialAt: indexPath.row)
        } else {
            delegate?.virtualMaterialSelectionViewController(self, didSelectMaterialAt: indexPath.row)
        }
        let material = VirtualMaterialDatabase.availableMaterials[indexPath.row]
        NotificationCenter.default.post(name: Notification.Name(rawValue: "materialChanged"), object: material)
        self.dismiss(animated: true, completion: nil)
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return VirtualMaterialDatabase.availableMaterials.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: MaterialCell.reuseIdentifier, for: indexPath) as? MaterialCell else {
            fatalError("Expected `MaterialCell` type for reuseIdentifier \(MaterialCell.reuseIdentifier). Check the configuration in Main.storyboard.")
        }
        cell.material = VirtualMaterialDatabase.availableMaterials[indexPath.row]
        if selectedVirtualMaterialRows.contains(indexPath.row) {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        cell?.backgroundColor = UIColor.lightGray.withAlphaComponent(0.5)
    }

    override func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        cell?.backgroundColor = UIColor.clear
    }

}

