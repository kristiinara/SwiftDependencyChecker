//
//  DependencyChecker.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 02.01.2022.
//

import Foundation

class DependencyChecker {
    let settings: Settings
    var onlyDirectDependencies = false
    var cpeOnlyFromFile = false
    
    init(settings: Settings) {
        self.settings = settings
    }
    
    func analyseAllLibraries() -> [String: (cpe: String, vulnerabilities: [CVEData])] {
        Logger.log(.info, "[*] Analysing all libraries.")
        
        var results: [String: (cpe: String, vulnerabilities: [CVEData])] = [:]
        
        let cpeFinder = CPEFinder(settings: settings)
        let vulnerabilityAnalyser = VulnerabilityAnalyser(settings: settings)
        
        for value in cpeFinder.cpeDictionary.dictionary {
            if let cpe = value.value.value {
                let vulnerabilities = vulnerabilityAnalyser.queryVulnerabilitiesFor(cpe: cpe)
                Logger.log(.debug, "[i] Found \(vulnerabilities.count) vulnerabilities.")
                results[value.key] = (cpe: cpe, vulnerabilities: vulnerabilities)
            }
        }
        
        return results
    }
    
    func analyseLibraries(filePath: String) -> [String: (cpe: String, vulnerabilities: [CVEData])] {
        Logger.log(.info, "[*] Analysing filePath: \(filePath) ...")
        
        var results: [String: (cpe: String, vulnerabilities: [CVEData])] = [:]
        
        do {
            let contents = try String(contentsOf: URL(fileURLWithPath: filePath))
            
            let cpeFinder = CPEFinder(settings: settings)
            cpeFinder.cpeOnlyFromFile = cpeOnlyFromFile
            
            let vulnerabilityAnalyser = VulnerabilityAnalyser(settings: settings)
            
            let lines = contents.components(separatedBy: .newlines)
            for line in lines {
                let libraryName = String(line)
                if libraryName.contains("/") {
                    Logger.log(.debug, "[*] Analysing: \(libraryName)...")
                    
                    if results.keys.contains(libraryName) {
                        Logger.log(.debug, "[i] Library already analysed, ignore.")
                        continue
                    }
                    
                    if let cpe = cpeFinder.findCPEForLibrary(name: libraryName) {
                        Logger.log(.debug, "[i] Found cpe: \(cpe)")
                        
                        let vulnerabilities = vulnerabilityAnalyser.queryVulnerabilitiesFor(cpe: cpe)
                        Logger.log(.debug, "[i] Found \(vulnerabilities.count) vulnerabilities.")
                        results[libraryName] = (cpe: cpe, vulnerabilities: vulnerabilities)
                        
                    } else {
                        Logger.log(.debug, "[i] No cpe found")
                    }
                    
                } else {
                    Logger.log(.debug, "[i] Ignoring line: \(libraryName)")
                }
            }
        } catch {
            Logger.log(.error, "[!] Could not read file: \(filePath)")
        }
        
        return results
    }
    
    func analyseFolder(path: String) -> [(library: Library, vulnerability: CVEData)] {
        Logger.log(.info, "[*] Analysing folder: \(path) ...")
        
        // find all dependencies:
        let analyser = DependencyAnalyser(settings: settings)
        analyser.onlyDirectDependencies = self.onlyDirectDependencies
        
        let libraries = analyser.analyseApp(folderPath: path)
        Logger.log(.info, "[i] Found \(libraries.count) dependencies.")
        Logger.log(.debug, "[i] Found dependencies: ")
        for library in libraries {
            var subTarget = ""
            if let value = library.subtarget {
                subTarget = " - \(value)"
            }
            
            if let direct = library.directDependency {
                if direct {
                    Logger.log(.debug, "[i] Direct: \(library.name) \(library.versionString)\(subTarget)")
                } else {
                    Logger.log(.debug, "[i] Indirect: \(library.name) \(library.versionString)\(subTarget)")
                }
            } else {
                Logger.log(.debug, "[i] Direct/Indirect: \(library.name) \(library.versionString)\(subTarget)")
            }
        }
        
        // find matching cpes:
        Logger.log(.info, "[*] Finding matching cpe values ...")
        
        var analysedLibraries: [AnalysedLibrary] = []
        libraryLoop: for library in libraries {
            Logger.log(.debug, "[*] Trying to match library: \(library.name), module: \(library.module ?? ""), subtarget: \(library.subtarget ?? "")")
            for analysedLibrary in analysedLibraries {
                if analysedLibrary.name == library.name {
                    analysedLibrary.versionsUsed.append(library)
                    continue libraryLoop
                }
            }
            let newAnalysedLibrary = AnalysedLibrary(name: library.name)
            newAnalysedLibrary.versionsUsed.append(library)
            analysedLibraries.append(newAnalysedLibrary)
        }
        
        let cpeFinder = CPEFinder(settings: settings)
        
        var count = 0
        for analysedLibrary in analysedLibraries {
            if let cpe = cpeFinder.findCPEForLibrary(name: analysedLibrary.name) {
                count += 1
                analysedLibrary.cpe = cpe
                Logger.log(.debug, "[i] For library \(analysedLibrary.name) found cpe: \(cpe)")
            }
        }
        Logger.log(.info, "[i] Found \(count) matching cpe values.")
        
        Logger.log(.info, "[*] Querying vulnerability for each found cpe value ...")
        // query vulnerabilities for each found cpe
        count = 0
        
        let vulnerabilityAnalyser = VulnerabilityAnalyser(settings: settings)
        for analysedLibrary in analysedLibraries {
            if let cpe = analysedLibrary.cpe {
                let cveData = vulnerabilityAnalyser.queryVulnerabilitiesFor(cpe: cpe)
                count += cveData.count
                analysedLibrary.vulnerabilities = cveData
                Logger.log(.debug, "[i] For library: \(analysedLibrary.name) found \(cveData.count) vulnerabilities")
            }
        }
        Logger.log(.info, "[i] Found \(count) possible vulnerabilities in used libraries.")
        
        // check if any of the used library versions are vulnerable
        Logger.log(.info, "[*] Matching vulnerable library versions to used library versions ...")
        
        var vulnerableVersionsUsed: [(library: Library, vulnerability: CVEData)] = []
        
        for library in analysedLibraries {
            Logger.log(.debug, "[i] For library \(library.name) following vulnerabilities were found:")
            let versions = library.vulnerableVersionsUsed
            vulnerableVersionsUsed.append(contentsOf: versions)
        }
        
        Logger.log(.info, "[i] In total \(vulnerableVersionsUsed.count) used vulnerable library versions found.")
        
        return vulnerableVersionsUsed
        
    }
}

class AnalysedLibrary {
    let name: String
    var versionsUsed: [Library] = []
    var cpe: String?
    var vulnerabilities: [CVEData] = []
    
    init(name: String) {
        self.name = name
    }
    
    var vulnerableVersionsUsed: [(library: Library, vulnerability: CVEData)] {
        var vulnerableVersions: [(library: Library, vulnerability: CVEData)] = []
        
        for vulnerability in vulnerabilities {
            Logger.log(.debug, "[*] Matching libraries to vulnerability: \(vulnerability.cve?.description ?? "")")
            if let versions = vulnerability.configuration?.affectedVersions {
            libraryLoop: for library in versionsUsed {
                    Logger.log(.debug, "[*] Matching to library: \(library.name)")
                    for version in versions {
                        Logger.log(.debug, "[*] Matching vulnerable version: \(version.versionString)")
                        let libraryVersion = Version(from: library.versionString)
                        Logger.log(.debug, "[*] Comparing to library version: \(library.versionString), \(version.versionString)")
                        if let libraryComparable = libraryVersion.comparableVersion {
                            if let exact = version.exactVersion {
                                Logger.log(.debug, "[*] Comparing exact matches")
                                let exactVersion = Version(from: exact)
                                
                                if let exactVersionComparable = exactVersion.comparableVersion {
                                    if libraryComparable == exactVersionComparable {
                                        Logger.log(.debug, "[i] Is a match")
                                        vulnerableVersions.append((library: library, vulnerability: vulnerability))
                                        continue libraryLoop
                                    } else {
                                        Logger.log(.debug, "[i] Is not a match ")
                                        continue 
                                    }
                                }
                            }
                            
                            if let endExcluding = version.versionEndExcluding {
                                Logger.log(.debug, "[*] Comparing End excluding: \(endExcluding)")
                                let endExcludingVersion = Version(from: endExcluding)
                                
                                if let endExcludingComparable = endExcludingVersion.comparableVersion {
                                    if libraryComparable >= endExcludingComparable {
                                        Logger.log(.debug, "[i] Not a match")
                                        continue
                                    }
                                } else {
                                    //TODO what do we do then? Currently will include it just in case
                                }
                            } else {
                                Logger.log(.debug, "[i] Not comparable \(version.versionEndExcluding ?? "")")
                            }
                            
                            if let endIncluding = version.versionEndIncluding {
                                Logger.log(.debug, "[*] Comparing End including: \(endIncluding)")
                                let endIncludingVersion = Version(from: endIncluding)
                                
                                if let endIncludingComparable = endIncludingVersion.comparableVersion {
                                    if libraryComparable > endIncludingComparable {
                                        Logger.log(.debug, "[i] Not a match.")
                                        continue
                                    }
                                }
                            } else {
                                Logger.log(.debug, "[i] Not comparable \(version.versionEndIncluding ?? "")")
                            }
                            
                            if let startExcluding = version.versionStartExcluding {
                                Logger.log(.debug, "[*] Comparing start excluding: \(startExcluding)")
                                let startExcludingVersion = Version(from: startExcluding)
                                
                                if let startExcludingComparable = startExcludingVersion.comparableVersion {
                                    if libraryComparable <= startExcludingComparable {
                                        Logger.log(.debug, "[i] Not a match.")
                                        continue
                                    }
                                }
                            } else {
                                Logger.log(.debug, "[i] Not comparable \(version.versionStartExcluding ?? "")")
                            }
                            
                            if let startIncluding = version.versionStartIncluding {
                                Logger.log(.debug, "[*] Comparing start including: \(startIncluding)")
                                let startIncludingVersion = Version(from: startIncluding)
                                
                                if let startIncludingComparable = startIncludingVersion.comparableVersion {
                                    if libraryComparable < startIncludingComparable {
                                        Logger.log(.debug, "Not a match")
                                        continue
                                    }
                                }
                            } else {
                                Logger.log(.debug, "[i] Not comparable \(version.versionStartIncluding ?? "")")
                            }
                            
                        } else {
                            Logger.log(.debug, "[i] Not comparable")
                        }
                        
                        Logger.log(.debug, "[i] Is a match")
                        vulnerableVersions.append((library: library, vulnerability: vulnerability))
                        continue libraryLoop
                    }
                }
            }
        }
    
        return vulnerableVersions
    }
    
    func parseVersion(versionString: String?) -> (major: Int, minor: Int, revision: Int)? {
        guard var version = versionString else {
            return nil
        }
        
        if version.starts(with: "v") {
            version = String(version.dropFirst())
        }
        
        let components = version.split(separator: ".")
        
        if components.count == 3 {
            if let major = Int(components[0]),
               let minor = Int(components[1]),
               let revision = Int(components[2]) {
                return (major: major, minor: minor, revision: revision)
            }
        }
        
        return nil
    }
}

class ComparableVersion: Comparable {
    let values: [Int]
    
    init(values: [Int]) {
        self.values = values
    }
    
    static func == (lhs: ComparableVersion, rhs: ComparableVersion) -> Bool {
        if lhs.values.count != rhs.values.count {
            return false
        }
        
        for i in 0...(lhs.values.count - 1) {
            if lhs.values[i] != lhs.values[i] {
                return false
            }
        }
        
        return true
    }
    
    static func < (lhs: ComparableVersion, rhs: ComparableVersion) -> Bool {
        Logger.log(.debug, "[*] Comparing: \(lhs.values) < \(rhs.values)")
        var total = 0
        if lhs.values.count > rhs.values.count {
            total = rhs.values.count
        } else {
            total = lhs.values.count
        }

        for i in 0...(total - 1) {
            if lhs.values[i] > rhs.values[i] {
                return false
            }
            
            if lhs.values[i] < rhs.values[i] {
                return true
            }
        }
        
        if lhs == rhs {
            return false
        }
        
        return true
    }
}

class Version {
    let versionString: String
    let comparableVersion: ComparableVersion?
    
    init(from: String) {
        self.versionString = from
        
        var version = from
        if version.starts(with: "v") {
            version = String(version.dropFirst())
        }
        
        let components = version.split(separator: ".")
        
        var parts: [Int] = []
        var incorrectValue = false
        
        for component in components {
            var stringValue = String(component)
            
            if stringValue.hasSuffix("-beta") {
                stringValue = stringValue.replacingOccurrences(of: "-beta", with: "")
            }
            
            if let intValue = Int(stringValue) {
                parts.append(intValue)
            } else {
                incorrectValue = true
            }
        }
        
        if !incorrectValue {
            self.comparableVersion = ComparableVersion(values: parts)
        } else {
            self.comparableVersion = nil
        }
    }
}
