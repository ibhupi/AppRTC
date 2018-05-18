//
//  ARTCRoomViewController.swift
//  AppRTCSwift
//
//  Created by Brandon Tyler on 8/14/17.
//  Copyright © 2017 Brandon Maynard. All rights reserved.
//

import UIKit

class ARTCRoomViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: true)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "RoomInputCell", for: indexPath) as? ARTCRoomTextInputViewCell else {
                print("ARTCRoomViewController: cellForRowAt indexPath: could not cast cell as ARTCRoomTextInputViewCell")
                return UITableViewCell()
            }
            cell.delegate = self
            
            return cell
        }
        return UITableViewCell()
    }
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let videoChatVC = segue.destination as? ARTCVideoChatViewController {
            guard let sender = sender as? String else {
                print("ARTCRoomViewController: prepare(for segue): Could not convert sender to type String")
                return
            }
            videoChatVC.setRoomName(name: sender)
        }
    }
}

extension ARTCRoomViewController: ARTCRoomTextInputViewCellDelegate {
    func roomTextInputView(cell: ARTCRoomTextInputViewCell, shouldJoin room: String) {
        self.performSegue(withIdentifier: "ARTCVideoChatViewController", sender: room)
    }
}

