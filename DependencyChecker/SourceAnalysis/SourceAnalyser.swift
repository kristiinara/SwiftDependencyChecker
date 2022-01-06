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
        os_log("analysing project files")
        var fileLocations: [FileLocation] = []
        
        let enumerator = FileManager.default.enumerator(atPath: path)
        while let filename = enumerator?.nextObject() as? String {
            //os_log(filename)
            if filename.hasSuffix(".swift") {
                let fullPath = "\(path)/\(filename)"
                os_log("fullpath: \(fullPath)")
                let url = URL(fileURLWithPath: fullPath)
                if let fileContents = try? String(contentsOf: url) {
                    let lines = fileContents.components(separatedBy: .newlines)
                    var count = 1
                    for var line in lines {
                        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.hasPrefix("import") {
                            let components = line.components(separatedBy: " ")
                            if components.count >= 2 {
                                let name = components[1]
                                os_log("import: \(name)")
                                for libraryDef in vulnerableLibraries {
                                    var libraryName = libraryDef.library.name.lowercased()
                                    if let module = libraryDef.library.module {
                                        libraryName = module.lowercased()
                                    }
                                    os_log("comparing to library: \(libraryName)")
                                    
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
