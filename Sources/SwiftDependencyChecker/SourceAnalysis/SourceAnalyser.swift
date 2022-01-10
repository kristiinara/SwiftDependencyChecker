//
//  SourceAnalyser.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 03.01.2022.
//

import Foundation
import os.log

class SourceAnalyser {
    func analyseProject(path: String, vulnerableLibraries: [(library: Library, vulnerability: CVEData)]) -> [FileLocation] {
        os_log(.info, "analysing project files")
        var fileLocations: [FileLocation] = []
        
        let enumerator = FileManager.default.enumerator(atPath: path)
        while let filename = enumerator?.nextObject() as? String {
            //os_log(filename)
            if filename.hasSuffix(".swift") || filename.hasSuffix("Podfile.lock") || filename.hasSuffix("Package.resolved") || filename.hasSuffix("Cartfile.resolved") {
                let fullPath = "\(path)/\(filename)"
                os_log(.debug, "fullpath: \(fullPath)")
                
                var detectedPlatform: String? = nil
                if filename.hasSuffix("Podfile.lock") {
                    detectedPlatform = "cocoapods"
                } else if filename.hasSuffix("Cartfile.resolved") {
                    detectedPlatform = "carthage"
                } else if filename.hasSuffix("Package.resolved") {
                    detectedPlatform = "swiftpm"
                }
                
                let url = URL(fileURLWithPath: fullPath)
                if let fileContents = try? String(contentsOf: url) {
                    let lines = fileContents.components(separatedBy: .newlines)
                    var count = 1
                    for var line in lines {
                        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if filename.hasSuffix("Podfile.lock") && line.hasPrefix("DEPENDENCIES:") {
                            break
                        }
                        
                        if line.hasPrefix("import") || line.hasPrefix("-") || line.hasPrefix("\"package\":") || filename.hasSuffix("Cartfile.resolved") {
                            
                            let components = line.components(separatedBy: " ")
                            if components.count >= 2 {
                                var name = components[1]
                                name = name.replacingOccurrences(of: "\"", with: "")
                                name = name.replacingOccurrences(of: ",", with: "")
                                
                                os_log(.debug, "import: \(name)")
                                for libraryDef in vulnerableLibraries {
                                    if let platform = libraryDef.library.platform, let detectedPlatform = detectedPlatform {
                                        if platform != detectedPlatform {
                                            continue
                                        }
                                    }
                                    
                                    var libraryName = libraryDef.library.name.lowercased()
                                    if let module = libraryDef.library.module {
                                        libraryName = module.lowercased()
                                    }
                                    
                                    if let subTarget = libraryDef.library.subtarget {
                                        libraryName = "\(libraryName)/\(subTarget)"
                                    }
                                    
                                    os_log(.debug, "comparing to library: \(libraryName)")
                                    
                                    if libraryName.hasSuffix("\(name.lowercased())") {
                                        var warning = "vulnerable"
                                        if let description = libraryDef.vulnerability.cve?.description {
                                            warning = description
                                        }
                                        
                                        let newlocation = FileLocation(path: fullPath, line: count, warning: warning)
                                        fileLocations.append(newlocation)
                                    }
                                }
                            }
                        }
                        count += 1
                    }
                }
            }
            
        }
        return fileLocations
    }
}

class FileLocation {
    let path: String
    let line: Int
    let warning: String
    
    init(path: String, line: Int, warning: String) {
        self.path = path
        self.line = line
        self.warning = warning
    }
}
