//
//  SettingsController.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 04.01.2022.
//

import Foundation
import os.log

class SettingsController {
    var settings: Settings
    var url: URL
    var folder: URL {
        didSet {
            self.url = self.folder.appendingPathComponent("settings.json")
        }
    }
    var changed = false
    
    init() {
        var home: URL
        if let path = UserDefaults.standard.url(forKey: "dependency_checker_files_path") {
            home = path
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
            home = home.appendingPathComponent("DependencyInfo", isDirectory: true)
        }
        
        self.folder = home
        self.url = self.folder.appendingPathComponent("settings.json")
        
        UserDefaults.standard.set(self.folder, forKey: "dependency_checker_files_path")
        
        if let data = try? Data(contentsOf: self.url) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(Settings.self, from: data) {
                settings = decoded
            } else {
                settings = Settings()
            }
        } else {
            settings = Settings()
        }
    }
    
    deinit {
        if changed {
            save()
        }
    }
    
    func save() {
        self.checkFolder()
        
        UserDefaults.standard.set(self.folder, forKey: "dependency_checker_files_path")
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self.settings) {
            do {
                try encoded.write(to: url)
            } catch {
                os_log("Could not save settings")
            }
        }
    }
    
    func checkFolder() {
        if !FileManager.default.fileExists(atPath: self.folder.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                os_log("Could not create folder: \(self.folder)")
            }
        }
    }
}

class Settings: Codable {
    var specTranslationTimeInterval: TimeInterval? =  7 * 60 * 60 * 24 //default one week
    var cpeTimeInterval: TimeInterval? = 7 * 60 * 60 * 24 //default one week
    var vulnerabilityTimeInterval: TimeInterval? = 1 * 60 * 60 * 24 // default one day
    var homeFolder: URL
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.homeFolder = home.appendingPathComponent("DependencyInfo", isDirectory: true)
    }
}


