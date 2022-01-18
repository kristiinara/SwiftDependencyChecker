//
//  CPEFinder.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 02.01.2022.
//

import Foundation
import Gzip

class CPEFinder {
    var cpeDictionary: CPEDictionary
    var url: URL
    var folder: URL
    var changed = false
    let settings: Settings
    var cpePath: URL
    
    init(settings: Settings) {
        self.folder = settings.homeFolder
        self.url = self.folder.appendingPathComponent("cpes.json")
        
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(CPEDictionary.self, from: data) {
                cpeDictionary = decoded
            } else {
                cpeDictionary = CPEDictionary(lastUpdated: Date())
            }
        } else {
            cpeDictionary = CPEDictionary(lastUpdated: Date())
        }
        
        self.settings = settings
        self.cpePath = self.settings.homeFolder.appendingPathComponent("official-cpe-dictionary_v2.3.xml", isDirectory: false)
        
        if self.checkCPEDatafile() == false {
            self.downloadCPEDataFile()
        }
        
        if self.shouldUpdate {
            self.update()
        }
    }
    
    var shouldUpdate: Bool {
        Logger.log(.info, "[i] Last updated cpe dictionary: \(self.cpeDictionary.lastUpdated)")
        
        if let timeInterval = self.settings.cpeTimeInterval {
            // check if time since last updated is larger than the allowed timeinterval for updates
            if self.cpeDictionary.lastUpdated.timeIntervalSinceNow * -1 > timeInterval {
                Logger.log(.info, "[i] Will update cpe dictionary")
                return true
            }
        }
        
        Logger.log(.info, "[i] No update for cpe dictionary")
        return false
    }
    
    func update() {
        Logger.log(.debug, "[*] Updating cpe dictionary")
        self.updateCPEDataFile()
        var updatedCPEs: [String: CPE] = [:]
        
        for cpe in self.cpeDictionary.dictionary {
            if cpe.value.value == nil {
                // ignore, these will be removed from cpes so that they can be updated
            } else {
                updatedCPEs[cpe.key] = cpe.value
            }
        }
        self.cpeDictionary.lastUpdated = Date()
        self.cpeDictionary.dictionary = updatedCPEs
        
        self.changed = true
    }
    
    func checkCPEDatafile() -> Bool{
        let path = self.cpePath.path
        
        Logger.log(.debug, "[*] Checking cpe data path: \(path)")
        let pathExists = FileManager.default.fileExists(atPath: path)
        Logger.log(.debug, "[i] Cpe data path exists: \(pathExists)")
        
        return pathExists
    }
    
    func downloadCPEDataFile() {
        Logger.log(.info, "[i] Downloading new CPE data file...")
        let downloadPath = "https://nvd.nist.gov/feeds/xml/cpe/dictionary/official-cpe-dictionary_v2.3.xml.gz"
        if let downloadURL = URL(string: downloadPath) {
            let gzipPath = self.cpePath.appendingPathExtension("gz")
            
            if let data = try? Data(contentsOf: downloadURL) {
                do {
                    try data.write(to: gzipPath)
                    let decompressedData = try data.gunzipped()
                    try decompressedData.write(to: self.cpePath)
                } catch {
                    Logger.log(.error, "[!] Downloading official cpe dictionary failed: \(error.localizedDescription)")
                }
            }
        } else {
            Logger.log(.error, "[!] Download path not a valid URL \(downloadPath)")
        }
    }
    
    func updateCPEDataFile() {
        Logger.log(.debug, "[*] Updateing CPE data file")
        do {
            try FileManager.default.removeItem(at: self.cpePath)
        } catch {
            Logger.log(.error, "[!] Removing cpe dictionary failed: \(error.localizedDescription)")
        }
        self.downloadCPEDataFile()
    }
    
    deinit {
        if changed {
            save()
        }
    }
    
    func save() {
        self.checkFolder()
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self.cpeDictionary) {
            do {
                try encoded.write(to: url)
            } catch {
                Logger.log(.error, "[!] Could not save cpes")
            }
        }
    }
    
    func checkFolder() {
        if !FileManager.default.fileExists(atPath: self.folder.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.log(.error, "[!] Could not create folder: \(self.folder)")
            }
        }
    }
    
    
    func findCPEForLibrary(name: String) -> String? {
        Logger.log(.debug, "[*] Finding CPE for library \(name)")
        if let cpe = self.cpeDictionary.dictionary[name] {
            Logger.log(.debug, "[i] Found existing CPE value: \(cpe.value)")
            return cpe.value
        }
        if name.contains("/") {
            let cpePath = self.cpePath.path

            if FileManager.default.fileExists(atPath: cpePath) {
                Logger.log(.debug, "[*] Searching for cpe for title: \(name)")
                Logger.log(.debug, "[*] Querying from file: \(cpePath) ...")
                
                if let cpeData = try? String(contentsOfFile: cpePath) {
                    let lines = cpeData.components(separatedBy: .newlines)
                    
                    var itemFound = false
                    var lineCount = 0
                    for var line in lines {
                        line = line.lowercased()
                        
                        if itemFound {
                            lineCount += 1
                        }
                        
                        if line.contains(name) {
                            itemFound = true
                            lineCount = 0
                        }
                        
                        if itemFound {
                            if line.contains("</cpe-item>") {
                                itemFound = false
                                lineCount = 0
                            }
                            
                            if line.contains("<cpe-23:cpe23-item name=\"") {
                                let components = line.components(separatedBy: "<cpe-23:cpe23-item name=\"")
                                if components.count > 0 {
                                    var value = components.last!
                                    value = value.replacingOccurrences(of: "\"/>", with: "")
                                    
                                    var splitValues = value.components(separatedBy: ":")
                                    splitValues[5] = "*"
                                    let cleanedCpe = "\(splitValues.joined(separator: ":"))"
                                    Logger.log(.debug, "[i] cleaned cpe: \(cleanedCpe)")
                                    
                                    self.cpeDictionary.dictionary[name] = CPE(value: cleanedCpe)
                                    self.changed = true
                                    
                                    return cleanedCpe
                                }
                            }
                        }
                    }
                } else {
                    Logger.log(.error, "[!] Could not read cpe file at \(cpePath)")
                }
            } else {
                Logger.log(.error, "[!] Cpe dictionary not found!")
            }
        } else {
            Logger.log(.debug, "[i] Name does not contain \"/\", ignore")
        }
        
        self.cpeDictionary.dictionary[name] = CPE(value: nil)
        self.changed = true
        
        return nil
    }
}

class CPEDictionary: Codable {
    var lastUpdated: Date
    var dictionary: [String: CPE]
    
    init(lastUpdated: Date) {
        self.lastUpdated = lastUpdated
        dictionary = [:]
    }
}

class CPE: Codable {
    var value: String?
    
    init(value: String?) {
        self.value = value
    }
}

