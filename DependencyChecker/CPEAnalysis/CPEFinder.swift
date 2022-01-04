//
//  CPEFinder.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 02.01.2022.
//

import Foundation
import os.log

class CPEFinder {
    func findCPEForLibrary(name: String) -> String? {
        if name.contains("/") {
            let cpePath = "/Users/kristiina/Phd/Tools/GraphifyEvolution/ExternalAnalysers/CPE/official-cpe-dictionary_v2.3.xml"

            if FileManager.default.fileExists(atPath: cpePath) {
                os_log("cpe for title: \(name)")
                
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
        
        return nil
    }
}


