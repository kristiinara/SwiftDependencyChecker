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
        subcommands: [Analyse.self, Setup.self],

        // A default subcommand, when provided, is automatically selected if a
        // subcommand is not given on the command line.
        defaultSubcommand: Analyse.self)
    
    struct Analyse: ParsableCommand {
        
        @Argument(help: "Path of the project to be analysed, if not specified the current directory is used. (optional)")
        var path: String
        
        enum Action: String, ExpressibleByArgument {
            case all, dependencies, findcpe, querycve
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
        
        mutating func run() {
            switch action {
            case .all:
                print("action: all")
            case .dependencies:
                print("action: dependencies")
            case .findcpe:
                print("action: findcpe")
            case .querycve:
                print("action: querycve")
            }
            
        }
    }
    
    struct Setup: ParsableCommand {
        mutating func run() {
            print("Setup -- not yet implemented")
        }
    }
}

