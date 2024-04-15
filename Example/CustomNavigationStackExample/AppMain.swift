//
//  CustomNavigationStackExampleApp.swift
//  CustomNavigationStackExample
//
//  Created by Quentin Fasquel on 15/04/2024.
//

import SwiftUI

@main
struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            ContentView(useCustomNavigationPath: true)
        }
    }
}
