//
//  DependencyChecker.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 02.01.2022.
//

import Foundation
import os.log

class DependencyChecker {
    let settings: Settings
    var onlyDirectDependencies = false
    
    init(settings: Settings) {
        self.settings = settings
    }
    
    func analyseFolder(path: String) -> [(library: Library, vulnerability: CVEData)] {
        
        // find all dependencies:
        let analyser = DependencyAnalyser(settings: settings)
        analyser.onlyDirectDependencies = self.onlyDirectDependencies
        
        let libraries = analyser.analyseApp(folderPath: path)
        os_log(.debug, "Dependencies: ")
        for library in libraries {
            var subTarget = ""
            if let value = library.subtarget {
                subTarget = " - \(value)"
            }
            
            if let direct = library.directDependency {
                if direct {
                    os_log(.debug, "\(library.name) \(library.versionString)\(subTarget)")
                } else {
                    os_log(.debug, "Indirect: \(library.name) \(library.versionString)\(subTarget)")
                }
            } else {
                os_log(.debug, "\(library.name) \(library.versionString)\(subTarget)")
            }
        }
        
        // find matching cpes:
        
        var analysedLibraries: [AnalysedLibrary] = []
        libraryLoop: for library in libraries {
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
        for analysedLibrary in analysedLibraries {
            if let cpe = cpeFinder.findCPEForLibrary(name: analysedLibrary.name) {
                analysedLibrary.cpe = cpe
                os_log(.debug, "for library \(analysedLibrary.name) found cpe: \(cpe)")
            }
        }
        
        // query vulnerabilities for each found cpe
        let vulnerabilityAnalyser = VulnerabilityAnalyser(settings: settings)
        for analysedLibrary in analysedLibraries {
            if let cpe = analysedLibrary.cpe {
                let cveData = vulnerabilityAnalyser.queryVulnerabilitiesFor(cpe: cpe)
                analysedLibrary.vulnerabilities = cveData
                os_log(.debug, "for library: \(analysedLibrary.name) found \(cveData.count) vulnerabilities")
            }
        }
        
        // check if any of the used library versions are vulnerable
        
        var vulnerableVersionsUsed: [(library: Library, vulnerability: CVEData)] = []
        
        for library in analysedLibraries {
            os_log(.debug, "For library \(library.name) following vulnerabilities were found:")
            let versions = library.vulnerableVersionsUsed
            vulnerableVersionsUsed.append(contentsOf: versions)
        }
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
            os_log(.debug, "vulnerability: \(vulnerability.cve?.description ?? "")")
            if let versions = vulnerability.configuration?.affectedVersions {
            libraryLoop: for library in versionsUsed {
                    os_log(.debug, "library: \(library.name)")
                    for version in versions {
                        os_log(.debug, "version: \(version.versionString)")
                        let libraryVersion = Version(from: library.versionString)
                        os_log(.debug, "compare: \(library.versionString), \(version.versionString)")
                        if let libraryComparable = libraryVersion.comparableVersion {
                            if let exact = version.exactVersion {
                                let exactVersion = Version(from: exact)
                                
                                if let exactVersionComparable = exactVersion.comparableVersion {
                                    if libraryComparable == exactVersionComparable {
                                        os_log(.debug, "is a match")
                                        vulnerableVersions.append((library: library, vulnerability: vulnerability))
                                        continue libraryLoop
                                    } else {
                                        os_log(.debug, "not a match ")
                                        continue 
                                    }
                                }
                            }
                            
                            if let endExcluding = version.versionEndExcluding {
                                let endExcludingVersion = Version(from: endExcluding)
                                
                                if let endExcludingComparable = endExcludingVersion.comparableVersion {
                                    if libraryComparable >= endExcludingComparable {
                                        os_log(.debug, "continue")
                                        continue
                                    }
                                } else {
                                    //TODO what do we do then? Currently will include it just in case
                                }
                            } else {
                                os_log(.debug, "not comparable \(version.versionEndExcluding ?? "")")
                            }
                            
                            if let endIncluding = version.versionEndIncluding {
                                let endIncludingVersion = Version(from: endIncluding)
                                
                                if let endIncludingComparable = endIncludingVersion.comparableVersion {
                                    if libraryComparable > endIncludingComparable {
                                        continue
                                    }
                                }
                            } else {
                                os_log(.debug, "not comparable \(version.versionEndIncluding ?? "")")
                            }
                            
                            if let startExcluding = version.versionStartExcluding {
                                let startExcludingVersion = Version(from: startExcluding)
                                
                                if let startExcludingComparable = startExcludingVersion.comparableVersion {
                                    if libraryComparable <= startExcludingComparable {
                                        continue
                                    }
                                }
                            } else {
                                os_log(.debug, "not comparable \(version.versionStartExcluding ?? "")")
                            }
                            
                            if let startIncluding = version.versionStartIncluding {
                                let startIncludingVersion = Version(from: startIncluding)
                                
                                if let startIncludingComparable = startIncludingVersion.comparableVersion {
                                    if libraryComparable < startIncludingComparable {
                                        continue
                                    }
                                }
                            } else {
                                os_log(.debug, "not comparable \(version.versionStartIncluding ?? "")")
                            }
                            
                        } else {
                            os_log(.debug, "not comparable")
                        }
                        
                        os_log(.debug, "is a match")
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
        os_log(.debug, "compare: \(lhs.values) < \(rhs.values)")
        var total = 0
        if lhs.values.count > rhs.values.count {
            total = rhs.values.count
        } else {
            total = lhs.values.count
        }
        
        os_log(.debug, "total: \(total)")
        os_log(.debug, "rhs.count \(rhs.values.count), lhs.values.count: \(lhs.values.count)")
        for i in 0...(total - 1) {
            os_log(.debug, "\(i) \(lhs.values[i]) > \(rhs.values[i] )")
            if lhs.values[i] > rhs.values[i] {
                os_log(.debug, "yes")
                return false
            }
            
            if lhs.values[i] < rhs.values[i] {
                return true
            }
            os_log(.debug, "no")
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
