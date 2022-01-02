//
//  CPEFinder.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 02.01.2022.
//

import Foundation

class CPEFinder {
    func findCPEForLibrary(name: String) -> String? {
        if name.contains("/") {
            let cpePath = "/Users/kristiina/Phd/Tools/GraphifyEvolution/ExternalAnalysers/CPE/official-cpe-dictionary_v2.3.xml"

            if FileManager.default.fileExists(atPath: cpePath) {
                print("cpe for title: \(name)")
                
                let output = Helper.shell(launchPath: "/bin/zsh", arguments: ["-c", "grep -A3 -i -e \(name) \(cpePath) | grep \"<cpe-23:cpe23-item name\""])
                print("cpe output: \(output)")
                if output != "" {
                    let items = output.components(separatedBy: "\n")
                    if items.count > 0 {
                        var first = items.first!
                        let components = first.components(separatedBy: "<cpe-23:cpe23-item name=\"")
                        if components.count > 0 {
                            first = components.last!
                            first = first.replacingOccurrences(of: "\"/>", with: "")
                            //print(first)
                            
                            var splitValues = first.components(separatedBy: ":")
                            splitValues[5] = "*"
                            let cleanedCpe = "\(splitValues.joined(separator: ":"))"
                            print("cleaned: \(cleanedCpe)")
                            
                            return cleanedCpe
                        }
                    }
                }
            } else {
                print("cpe dictionary not found!")
            }
        } else {
            print("name does not contain \"/\"")
        }
        
        return nil
    }
}


