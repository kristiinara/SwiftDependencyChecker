//
//  CPEFinder.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 02.01.2022.
//

import Foundation
import os.log

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
        if let timeInterval = self.settings.cpeTimeInterval {
            // check if time since last updated is larger than the allowed timeinterval for updates
            if self.cpeDictionary.lastUpdated.timeIntervalSinceNow * -1 > timeInterval {
                return true
            }
        }
        
        return false
    }
    
    func update() {
        os_log("update cpe data file")
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
        
        os_log("check cpe data path: \(path)")
        let pathExists = FileManager.default.fileExists(atPath: path)
        os_log("path exists: \(pathExists)")
        
        return pathExists
    }
    
    func downloadCPEDataFile() {
        let downloadPath = "https://nvd.nist.gov/feeds/xml/cpe/dictionary/official-cpe-dictionary_v2.3.xml.gz"
        if let downloadURL = URL(string: downloadPath) {
            let gzipPath = self.cpePath.appendingPathExtension("gz")
            
            if let data = try? Data(contentsOf: downloadURL) {
                do {
                    try data.write(to: gzipPath)
                    let res = Helper.shell(launchPath: "/usr/bin/gzip", arguments: ["-d", gzipPath.path])
                    os_log("Unzipping: \(res)")
                } catch {
                    os_log("Downloading official cpe dictionary failed: \(error.localizedDescription)")
                }
            }
        } else {
            os_log("Download path not a valid URL \(downloadPath)")
        }
    }
    
    func updateCPEDataFile() {
        do {
            try FileManager.default.removeItem(at: self.cpePath)
        } catch {
            os_log("Removing cpe dictionary failed: \(error.localizedDescription)")
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
                os_log("Could not save cpes")
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
    
    
    func findCPEForLibrary(name: String) -> String? {
        if let cpe = self.cpeDictionary.dictionary[name] {
            return cpe.value
        }
        
        if name.contains("/") {
            let cpePath = self.cpePath.path

            if FileManager.default.fileExists(atPath: cpePath) {
                os_log("cpe for title: \(name)")
                os_log("querying from file: \(cpePath)")
                
                let output = Helper.shell(launchPath: "/bin/zsh", arguments: ["-c", "grep -A3 -i -e \(name) \(cpePath) | grep \"<cpe-23:cpe23-item name\""])
                os_log("cpe output: \(output)")
                if output != "" {
                    let items = output.components(separatedBy: "\n")
                    if items.count > 0 {
                        var first = items.first!
                        let components = first.components(separatedBy: "<cpe-23:cpe23-item name=\"")
                        if components.count > 0 {
                            first = components.last!
                            first = first.replacingOccurrences(of: "\"/>", with: "")
                            //os_log(first)
                            
                            var splitValues = first.components(separatedBy: ":")
                            splitValues[5] = "*"
                            let cleanedCpe = "\(splitValues.joined(separator: ":"))"
                            os_log("cleaned: \(cleanedCpe)")
                            
                            self.cpeDictionary.dictionary[name] = CPE(value: cleanedCpe)
                            self.changed = true
                            
                            return cleanedCpe
                        }
                    }
                }
            } else {
                os_log("cpe dictionary not found!")
            }
        } else {
            os_log("name does not contain \"/\"")
        }
        
        self.cpeDictionary.dictionary[name] = CPE(value: nil)
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

