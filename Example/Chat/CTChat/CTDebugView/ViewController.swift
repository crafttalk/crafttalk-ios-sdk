//
//  ViewController.swift
//  Chat
//
//  Created by philip on 12.07.2023.
//  Copyright © 2023 Igor Bopp. All rights reserved.
//

import UIKit

class DebugViewController: UIViewController {

    @IBOutlet weak var printAllUser: UIButton!
    
    @IBOutlet weak var CloseWebChatWindow: UIButton!
    
    @IBOutlet weak var AcceptChangeUser: UIButton!
    
    @IBOutlet weak var UserNumberField: UITextField!
    
    @IBOutlet weak var ChangeUserField: UITextField!
    
    @IBOutlet weak var DeleteAllUser: UIButton!
    
    @IBAction func DeleteAllUser(_ sender: Any) {
        CTChat.shared.userList.removeAll()
        CTChat.shared.saveUserList()
        
    }
    
    @IBAction func ChangeUser(_ sender: Any) {
        var string: String = ChangeUserField.text ?? ""
        var number: Int = Int(string) ?? 0
        CTChat.shared.switchUser(number)
    }
    
    @IBAction func printAllUser(_ sender: Any) {
    }
    
    @IBAction func CloseChatWindow(_ sender: Any) {
        //CTChatViewController.de
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
