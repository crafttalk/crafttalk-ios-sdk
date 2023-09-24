//
//  ViewControllerRegistration.swift
//  Chat
//
//  Created by philip on 10.07.2023.
//  Copyright © 2023 Igor Bopp. All rights reserved.
//

import UIKit

class CTViewControllerRegistration: UIViewController {
    
    private var visitor: CTVisitor!
    
    // MARK: - Objects from scene
    //Описание объектов из окна регистрации из storyboard
    @IBOutlet weak var nameField: UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var registrationButton: UIButton!
    @IBOutlet weak var logInButton: UIButton!
    
    @IBOutlet weak var nameField2: UITextField!
    
    // MARK: - We Did Load
    // функция запускается после самого первого открытия текущего окна, при повторном открытии не вызывается
    override func viewDidLoad() {
        super.viewDidLoad()   
        //print("Registration window loaded!")
        
        // Do any additional setup after loading the view.
    }
    // MARK: - Action
    @IBAction func confirmRegistration(_ sender: Any) {
        
        let nameData: String = nameField.text ?? ""
        let uuid = UUID().uuidString
        
        let visitor = CTVisitor(firstName: nameData, lastName: "", uuid: uuid, customProperties: ["custom" : "123"])
        
        CTChat.shared.registerVisitor(visitor)
        if CTChat.shared.userList[0].firstName == "Anonymous" {
            CTChat.shared.userList.remove(at: 0)
        }
        CTChat.shared.saveUserList()
    }
    
    @IBAction func confirmLogIn(_ sender: Any) {
        print("LOGIN CONFIRMED!")
        //сюда вставить код извлекающий данные и сохраняющий
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
