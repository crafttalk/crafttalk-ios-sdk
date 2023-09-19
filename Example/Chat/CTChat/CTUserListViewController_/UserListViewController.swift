//
//  UserListViewController.swift
//  Chat
//
//  Created by philip on 13.07.2023.
//  Copyright © 2023 Igor Bopp. All rights reserved.
//

import UIKit

class UserListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    ///Список имён пользователей, формируемый из списка всех пользователей, при открытии окна
    var wordList: [String] = ["Ошибка", "Загрузки", "Имён", "Пользователей"]
    
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var RightBarButton: UIBarButtonItem!
    
    ///Функция переключает список в режим удаления пользователей
    @IBAction func ChangeEditingMode(_ sender: Any) {
        if tableView.isEditing == true {
            tableView.isEditing = false
        } else
        {
            tableView.isEditing = true
        }
    }
    public override func viewWillAppear(_ animated: Bool) {
        print ("user window reopen!")
        tableView.isEditing = false
        if wordList.count != CTChat.shared.userList.count {
            print ("New user register")
            updatelist()
            tableView.reloadData()
        }
        if CTChat.shared.userList.count == 1 {
            updatelist()
            tableView.reloadData()
        }
    
    }

    override func viewDidLoad() {
            super.viewDidLoad()
            updatelist()
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WordCell")
            tableView.dataSource = self
            tableView.delegate = self // Установите делегат UITableViewDelegate
            tableView.isEditing = false
        }
        
        // MARK: - Table View Data Source
        

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return wordList.count
        }
        
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "WordCell", for: indexPath)
            cell.textLabel?.text = wordList[indexPath.row]
            
            return cell
        }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            let selectedWord = wordList[indexPath.row]
            print("Выбрано слово: \(selectedWord)")
        let alertController = UIAlertController(title: "User selected",
                                                        message: selectedWord,
                                                        preferredStyle: .alert)
                
                let okAction = UIAlertAction(title: "Fine!", style: .default, handler: nil)
                alertController.addAction(okAction)
                
                present(alertController, animated: true, completion: nil)
        CTChat.shared.currentUserID = indexPath.row
        CTChat.shared.switchUserChanger()
        print(CTChat.shared.currentUserID)
            // Здесь вы можете выполнить дополнительные действия при нажатии на ячейку
        }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            if editingStyle == .delete {
                wordList.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .fade)
                
            }
        CTChat.shared.deleteUser(indexPath.row)
        CTChat.shared.saveUserList()
        }
    ///Обновляет список имён пользователей
    func updatelist(){
        wordList.removeAll()
        for i in stride (from: 0, through: CTChat.shared.userList.count - 1, by: +1){
            wordList.append(CTChat.shared.userName(i) + CTChat.shared.userLastName(i))
        }
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
