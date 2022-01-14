//
//  main.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 31.12.2021.
//

import Foundation
import ArgumentParser


// Find dependencies:
// in current folder find Carthage.resolved, PodFile.resolved and Package.resolved (all the same ending?) files
// go through files and find dependencies

// if PodFile, then translate pod name to github username/name (what to do with stuff that is not open source?)
// write found Libraries (name + version + type of dependency) into a json file

// MatchCPE
// given name of libraries find corresponding cpe
// add this to Library info and save into json file

// QueryNVD
// given cpe-s find cve-s
// write info into json file

// now for each Library go through found cve-s and check if the given version is vulnerable
// output result + save into json


Application.main()

struct Application: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "DependencyChecker is a tool that analyses project dependencies declared in Carthage, CocoaPods and Swift Package manager. The dependent libraries are identified, then the NVD database is queried to check if the libraries and library versions used are vulnerable.",
        // Commands can define a version for automatic '--version' support.
        version: "0.0.1",
        subcommands: [Analyse.self, ToolSettings.self],

        // A default subcommand, when provided, is automatically selected if a
        // subcommand is not given on the command line.
        defaultSubcommand: Analyse.self)
    
    struct Analyse: ParsableCommand {
        
        @Argument(help: "Path of the project to be analysed, if not specified the current directory is used. (optional)")
        var path: String = FileManager.default.currentDirectoryPath
        
        enum Action: String, ExpressibleByArgument {
            case all, dependencies, findcpe, querycve, sourceanalysis, translate
        }
        @Option(help: "Action to take. Dependencies detects the dependencies declared. Findcpe finds the corresponding cpe for each library, querycve queries cve-s from NVD database.")
        var action: Action = .all
        
        enum Platform: String, ExpressibleByArgument {
            case carthage, cocoapods, swiftpm, all
        }
        @Option(help: "Package manager that should be analysed. Either cocoapods, carthage, swiftpm or all (default). (optional)")
        var platform: Platform = .all
        
        @Flag(help: "Find package manager artifacts recursevly in subfolders (default false).")
        var subFolders: Bool = false
        
        @Option(help: "Spcify a specific value for the selected action. For depenencies a specific manifest file can be provided, for dindcpe a specific library name can be provided and for querycve a specific cpe string can be provided.")
        var specificValue: String?
        
        @Flag(help: "Analyse only direct dependencies.")
        var onlyDirectDependencies = false
        
        mutating func run() {
            print("path: \(path)")
            
            let settings = Settings()
            
            switch action {
            case .all:
                print("action: all")
                let analyser = DependencyChecker(settings: settings)
                analyser.onlyDirectDependencies = onlyDirectDependencies
                
                let vulnerableVersionsUsed = analyser.analyseFolder(path: path)
                
                for vulnerableVersion in vulnerableVersionsUsed {
                    var subTarget = ""
                    if let value = vulnerableVersion.library.subtarget {
                        subTarget = " - \(value)"
                    }
                    
                    print("  --  \(vulnerableVersion.library.name) - \(vulnerableVersion.library.versionString)\(subTarget)")
                    if let description = vulnerableVersion.vulnerability.cve?.description {
                        print("  --  description: \(description)")
                    }
                }
            case .sourceanalysis:
                let analyser = DependencyChecker(settings: settings)
                analyser.onlyDirectDependencies = onlyDirectDependencies
                let vulnerableVersionsUsed = analyser.analyseFolder(path: path)
                
                /*
                for vulnerableVersion in vulnerableVersionsUsed {
                    var subTarget = ""
                    if let value = vulnerableVersion.library.subtarget {
                        subTarget = " - \(value)"
                    }
                    
                    print("  --  \(vulnerableVersion.library.name) - \(vulnerableVersion.library.versionString)\(subTarget)")
                    if let description = vulnerableVersion.vulnerability.cve?.description {
                        print("  --  description: \(description)")
                    }
                }
                 */
                let sourceAnalyser = SourceAnalyser()
                let locations = sourceAnalyser.analyseProject(path: path, vulnerableLibraries: vulnerableVersionsUsed)
                
                for location in locations {
                    print("\(location.path):\(location.line):8: warning: \(location.warning) (vulnerable version)")
                }
            case .dependencies:
                print("action: dependencies")
                let analyser = DependencyAnalyser(settings: settings)
                analyser.onlyDirectDependencies = onlyDirectDependencies
                let libraries = analyser.analyseApp(folderPath: path)
                print("Dependencies: ")
                for library in libraries {
                    var subTarget = ""
                    if let value = library.subtarget {
                        subTarget = " sub-target:\(value)"
                    }
                    
                    var module = ""
                    if let value = library.module {
                        module = " module:\(value)"
                    }
                    
                    var platform = ""
                    if let value = library.platform {
                        platform = "platform:\(value) "
                    }
                    
                    let dataString = "\(platform)name:\(library.name) version:\(library.versionString)\(subTarget)\(module)"
                    
                    if let direct = library.directDependency {
                        if direct {
                            print(dataString)
                        } else {
                            print("Indirect \(dataString)")
                        }
                    } else {
                        print(dataString)
                    }
                }
            case .findcpe:
                print("action: findcpe")
                let analyser = CPEFinder(settings: settings)
                if let specificValue = specificValue {
                    print("For library name: \(specificValue)")
                    if let cpe = analyser.findCPEForLibrary(name: specificValue) {
                        print("found cpe: \(cpe)")
                    } else {
                        print("no found cpe")
                    }
                } else {
                    print("Currently only analysis with specific value supported.")
                }
            case .querycve:
                print("action: querycve")
                let analyser = VulnerabilityAnalyser(settings: settings)
                if let specificValue = specificValue {
                    print("Vulnerabilities for cpe: \(specificValue)")
                    //TODO: check if cpe has correct format??
                    
                    let cveList = analyser.queryVulnerabilitiesFor(cpe: specificValue)
                    print("Found vulnerabilities: \(cveList)")
                    for cve in cveList {
                        if let description = cve.cve?.description {
                            print("Vulnerability: \(description)")
                            if let configuration = cve.configuration {
                                let affectedVersions = configuration.affectedVersions
                                for version in affectedVersions {
                                    print("    cpe: \(version.cpeString)")
                                    if let value = version.versionStartIncluding {
                                        print("    startincluding: \(value)")
                                    }
                                    
                                    if let value = version.versionStartExcluding {
                                        print("    startexcluding: \(value)")
                                    }
                                    if let value = version.versionEndIncluding {
                                        print("    endtincluding: \(value)")
                                    }
                                    if let value = version.versionEndExcluding {
                                        print("    endtexcluding: \(value)")
                                    }
                                }
                            }
                        } else {
                            print("no description")
                        }
                    }
                } else {
                    print("Currently only analysis with specific value supported.")
                }
                
            case .translate:
                print("action: translate")
                let analyser = DependencyAnalyser(settings: settings)
                if let specificValue = specificValue {
                    let components = specificValue.split(separator: ",")
                    if components.count == 2 {
                        let name = String(components[0]).lowercased()
                        let version = String(components[1])
                        print("name: \(name), version: \(version)")
                        
                        if let translation = analyser.translateLibraryVersion(name: name, version: version) {
                            print("translation: \(translation.name.lowercased()):\(translation.version ?? String(components[1]))")
                        } else {
                            print("no translation")
                        }
                    } else {
                        print("Specific value should be of form: name,version")
                    }
                } else {
                    print("Currently only analysis with specific value supported.")
                }
            }
            
        }
    }
    
    struct ToolSettings: ParsableCommand {
        enum Action: String, ExpressibleByArgument {
            case get, set, displayall
        }
        @Option(help: "Action to take. Dependencies detects the dependencies declared. Findcpe finds the corresponding cpe for each library, querycve queries cve-s from NVD database.")
        var action: Action = .displayall
        
        
        enum Property: String, ExpressibleByArgument {
            case homeFolder, specTimeInterval, cpeTimeInterval, vulnerabilityTimeInterval, specDirectory
        }
        @Option(help: "which value to set or get")
        var property: Property?
        
        @Option(help: "which value to set or get")
        var value: String?
        
        mutating func run() {
            var settingsController = SettingsController()
            
            print("Settings")
            switch action {
            case .get:
                if let property = property {
                    switch property {
                    case .homeFolder:
                        print("\(settingsController.settings.homeFolder)")
                    case .specDirectory:
                        print("\(settingsController.settings.specDirectory)")
                    case .specTimeInterval:
                        print("\(settingsController.settings.specTranslationTimeInterval)")
                    case .cpeTimeInterval:
                        print("\(settingsController.settings.cpeTimeInterval)")
                    case .vulnerabilityTimeInterval:
                        print("\(settingsController.settings.vulnerabilityTimeInterval)")
                    }
                } else {
                    print("Property not defined.")
                }
            case .set:
                if let property = property, let value = value {
                    switch property {
                    case .homeFolder:
                        let url = URL(fileURLWithPath: value)
                        settingsController.folder = url
                        settingsController.settings.homeFolder = url
                        settingsController.changed = true
                    case .specDirectory:
                        let url = URL(fileURLWithPath: value)
                        settingsController.settings.specDirectory = url
                        settingsController.changed = true
                        // TODO: chould this be also changed if the main url is changed?
                    case .specTimeInterval:
                        if let timeInterval = TimeInterval(value) {
                            settingsController.settings.specTranslationTimeInterval = timeInterval
                            settingsController.changed = true
                        } else {
                            print("Value \(value) not a time interval.")
                        }
                    case .cpeTimeInterval:
                        if let timeInterval = TimeInterval(value) {
                            settingsController.settings.cpeTimeInterval = timeInterval
                            settingsController.changed = true
                        } else {
                            print("Value \(value) not a time interval.")
                        }
                    case .vulnerabilityTimeInterval:
                        if let timeInterval = TimeInterval(value) {
                            settingsController.settings.vulnerabilityTimeInterval = timeInterval
                            settingsController.changed = true
                        } else {
                            print("Value \(value) not a time interval.")
                        }
                    }
                } else {
                    print("Property or value not defined.")
                }
            case .displayall:
                print("Homefolder: \(settingsController.settings.homeFolder)")
                print("TimeInterval for spec analysis: \(settingsController.settings.specTranslationTimeInterval)")
                print("TimeInterval for cpe analysis: \(settingsController.settings.cpeTimeInterval)")
                print("TimeInterval for vulnerability analysis: \(settingsController.settings.vulnerabilityTimeInterval)")
            }
        }
    }
}

