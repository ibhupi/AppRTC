//
//  ARTCRoomTextInputViewCell.swift
//  AppRTCSwift
//
//  Created by Brandon Tyler on 8/14/17.
//  Copyright © 2017 Brandon Maynard. All rights reserved.
//

import Foundation

protocol ARTCRoomTextInputViewCellDelegate: class {
    func roomTextInputView(cell: ARTCRoomTextInputViewCell, shouldJoin room: String)
}

class ARTCRoomTextInputViewCell: UITableViewCell {
    var delegate: ARTCRoomTextInputViewCellDelegate?
    
    @IBOutlet weak var textField: UITextField!
    @IBOutlet weak var textFieldBorderView: UIView!
    @IBOutlet weak var joinButton: UIButton!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var errorLabelHeightConstraint: NSLayoutConstraint! // used for animating
    
    override func awakeFromNib() {
        // Initialization code
        self.errorLabelHeightConstraint.constant = 0.0
        self.textField.delegate = self
        self.textField.becomeFirstResponder()
        self.joinButton.backgroundColor = UIColor.init(white: 100/255, alpha: 1.0)
        self.joinButton.isEnabled = false
        self.joinButton.layer.cornerRadius = 3.0
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        // Configure the view for the selected state
    }
    
    @IBAction func touchButtonPressed(_ sender: UIButton) {
        guard let room = self.textField.text else {
            print("ARTCRoomTextInputViewCell: touchButtonPressed: textField has no text")
            return
        }
        delegate?.roomTextInputView(cell: self, shouldJoin: room)
    }
}

extension ARTCRoomTextInputViewCell: UITextFieldDelegate {
    
    // MARK: - UITextFieldDelegate Methods
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // No Implementation
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let isBackspace = string == "" && range.length == 1
        var text = "\(textField.text ?? "")\(string)"
        
        if isBackspace && text.count > 1 {
            let newText = text.dropLast(2)
            text = String(newText)
        }
        if text.count >= 5 {
            UIView.animate(withDuration: 0.3, animations: { [weak self] in
                self?.errorLabelHeightConstraint.constant = 0.0
                self?.textFieldBorderView.backgroundColor = UIColor(red: 66.0/255.0, green: 133.0/255.0, blue: 244.0/255.0, alpha: 1.0)
                self?.joinButton.backgroundColor = UIColor(red: 66.0/255.0, green: 133.0/255.0, blue: 244.0/255.0, alpha: 1.0)
                self?.joinButton.isEnabled = true
                self?.layoutIfNeeded()
            })
        } else {
            UIView.animate(withDuration: 0.3, animations: { [weak self] in
                self?.errorLabelHeightConstraint.constant = 40.0
                self?.textFieldBorderView.backgroundColor = UIColor(red: 244.0/255.0, green: 67.0/255.0, blue: 54.0/255.0, alpha: 1.0)
                self?.joinButton.backgroundColor = UIColor(white: 100.0/255.0, alpha: 1.0)
                self?.joinButton.isEnabled = false
                self?.layoutIfNeeded()
            })
        }
        return true
    }
}
