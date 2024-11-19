//
//  SwiftNote_AIApp.swift
//  SwiftNote AI
//
//  Created by Serkan Kutlubay on 11/19/24.
//

import SwiftUI

@main
struct SwiftNote_AIApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
