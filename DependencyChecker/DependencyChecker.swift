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
        os_log("Dependencies: ")
        for library in libraries {
            var subTarget = ""
            if let value = library.subtarget {
                subTarget = " - \(value)"
            }
            
            if let direct = library.directDependency {
                if direct {
                    os_log("\(library.name) \(library.versionString)\(subTarget)")
                } else {
                    os_log("Indirect: \(library.name) \(library.versionString)\(subTarget)")
                }
            } else {
                os_log("\(library.name) \(library.versionString)\(subTarget)")
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
                os_log("for library \(analysedLibrary.name) found cpe: \(cpe)")
            }
        }
        
        // query vulnerabilities for each found cpe
        let vulnerabilityAnalyser = VulnerabilityAnalyser(settings: settings)
        for analysedLibrary in analysedLibraries {
            if let cpe = analysedLibrary.cpe {
                let cveData = vulnerabilityAnalyser.queryVulnerabilitiesFor(cpe: cpe)
                analysedLibrary.vulnerabilities = cveData
                os_log("for library: \(analysedLibrary.name) found \(cveData.count) vulnerabilities")
            }
        }
        
        // check if any of the used library versions are vulnerable
        
        var vulnerableVersionsUsed: [(library: Library, vulnerability: CVEData)] = []
        
        for library in analysedLibraries {
            os_log("For library \(library.name) following vulnerabilities were found:")
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
            if let versions = vulnerability.configuration?.affectedVersions {
                for version in versions {
                    for library in versionsUsed {
                        if let libraryVersion = parseVersion(versionString: library.versionString) {
                        
                            if let endExcluding = parseVersion(versionString: version.versionEndExcluding) {
                                if libraryVersion.major > endExcluding.major {
                                    continue
                                }
                                
                                if libraryVersion.minor > endExcluding.minor {
                                    continue
                                }
                                
                                if libraryVersion.revision > endExcluding.revision {
                                    continue
                                }
                                
                                if libraryVersion == endExcluding {
                                    continue
                                }
                            }
                            
                            if let endIncluding = parseVersion(versionString: version.versionEndIncluding) {
                                    if libraryVersion.major > endIncluding.major {
                                        continue
                                    }
                                    
                                    if libraryVersion.minor > endIncluding.minor {
                                        continue
                                    }
                                    
                                    if libraryVersion.revision > endIncluding.revision {
                                        continue
                                    }
                            }
                            
                            if let startIncluding = parseVersion(versionString: version.versionStartIncluding) {
                                if libraryVersion.major < startIncluding.major {
                                    continue
                                }
                                
                                if libraryVersion.minor < startIncluding.minor {
                                    continue
                                }
                                
                                if libraryVersion.revision < startIncluding.revision {
                                    continue
                                }
                            }
                            
                            if let startExcluding = parseVersion(versionString: version.versionStartExcluding) {
                                if libraryVersion.major < startExcluding.major {
                                    continue
                                }
                                
                                if libraryVersion.minor < startExcluding.minor {
                                    continue
                                }
                                
                                if libraryVersion.revision < startExcluding.revision {
                                    continue
                                }
                                
                                if libraryVersion == startExcluding {
                                    continue
                                }
                            }
                        } else {
                            os_log("Cannot parse library version \(library.versionString)")
                        }
                        
                        vulnerableVersions.append((library: library, vulnerability: vulnerability))
                    }
                }
            }
        }
    
        return vulnerableVersions
    }
    
    func parseVersion(versionString: String?) -> (major: Int, minor: Int, revision: Int)? {
        guard let version = versionString else {
            return nil
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
