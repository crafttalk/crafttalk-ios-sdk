//
//  SwiftUIView.swift
//  Chat
//
//  Created by philip on 05.07.2023.
//  Copyright © 2023 Igor Bopp. All rights reserved.
//

import SwiftUI

@available(iOS 14.0, *)

struct Sidebar: View {
    var body: some View{
        NavigationView(){
            List {
                NavigationLink(destination: userlist()){
                    Label ("Set user", systemImage: "book")
                    
                }
                NavigationLink(destination: registration()){
                    Label ("Registration", systemImage: "book")
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Users")
        }
        }
    }

@available(iOS 14.0, *)

struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        Sidebar()
    }
}
