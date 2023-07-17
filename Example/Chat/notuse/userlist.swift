//
//  userlist.swift
//  Chat
//
//  Created by philip on 05.07.2023.
//  Copyright © 2023 Igor Bopp. All rights reserved.
//

import SwiftUI

@available(iOS 14.0, *)
struct userlist: View {
    var body: some View {
        NavigationView(){
            List{
                VStack{
                    HStack{Image("home");Text("Hello, World!");Button("Set") {
                        /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Action@*/ /*@END_MENU_TOKEN@*/
                    }
                    }
                    HStack{Image("home");Text("Hello, World!");Button("Set") {
                        /*@START_MENU_TOKEN@*//*@PLACEHOLDER=Action@*/ /*@END_MENU_TOKEN@*/
                    }
                    }
                    HStack{Image("home");Text("Hello, World!");Button("Set") {
                        
                    }
                    }
                    
                    
                }
            }
        }
    }
}
@available(iOS 14.0, *)
struct userlist_Previews: PreviewProvider {
    static var previews: some View {
        userlist()
    }
}
