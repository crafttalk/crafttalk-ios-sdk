//
//  registration.swift
//  Chat
//
//  Created by philip on 05.07.2023.
//  Copyright © 2023 Igor Bopp. All rights reserved.
//

import SwiftUI
@available(iOS 14.0, *)

var var1:String?

@available(iOS 14.0, *)
struct registration: View {
    var body: some View {
        VStack{
            Text("Registration")
            Form {
                HStack(){
                    Text("login ")
                    TextField(/*@START_MENU_TOKEN@*/"Placeholder"/*@END_MENU_TOKEN@*/, text: /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Value@*/.constant("")/*@END_MENU_TOKEN@*/)}
                HStack{
                    Text("password ")
                    TextField(/*@START_MENU_TOKEN@*/"Placeholder"/*@END_MENU_TOKEN@*/, text: /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Value@*/.constant("")/*@END_MENU_TOKEN@*/)
                }
            }
            HStack{
                Button("Login") {
                    /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Action@*/ /*@END_MENU_TOKEN@*/
                }
                
                Button("Registration") {
                    /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Action@*/ /*@END_MENU_TOKEN@*/
                }
            }
        }
        
    }
}
@available(iOS 14.0, *)
struct registration_Previews: PreviewProvider {
    static var previews: some View {
        registration()
    }
}
