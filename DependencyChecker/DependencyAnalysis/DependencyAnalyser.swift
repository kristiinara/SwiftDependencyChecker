//
//  DependencyAnalyser.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 01.01.2022.
//
import Foundation

class DependencyAnalyser {
    var libraryDictionary: [String: (name: String, path: String?, versions: [String:String])] = [:]
    
    func getNameFromGitPath(path: String) -> String? {
        var libraryName: String? = nil
        if path.contains(".com") {
            libraryName = path.components(separatedBy: ".com").last!.replacingOccurrences(of: ".git", with: "")
        } else if path.contains(".org") {
            libraryName = path.components(separatedBy: ".org").last!.replacingOccurrences(of: ".git", with: "")
        }
        
        if var foundName = libraryName {
            foundName = foundName.lowercased()
            foundName.removeFirst()
            libraryName = foundName
        }
        
        return libraryName
    }
        
    func translateLibraryVersion(name: String, version: String) -> (name: String, version: String?)? {
        print("translate library name: \(name), version: \(version)")
        
       // let currentDirectory = FileManager.default.currentDirectoryPath
        let currentDirectory = "/Users/kristiina/Phd/Tools/GraphifyEvolution"
        //print("currnent directory: \(currentDirectory)")
        let specDirectory = "\(currentDirectory)/ExternalAnalysers/Specs/Specs" // TODO: check that the repo actually exists + refresh?
        //print("specpath: \(specDirectory)")
        
        if var translation = libraryDictionary[name] {
            if let translatedVersion = translation.versions[version] {
                return (name:translation.name, version: translatedVersion)
            } else {
                if let path = translation.path {
                    let enumerator = FileManager.default.enumerator(atPath: path)
                    var podSpecPath: String? = nil
                    while let filename = enumerator?.nextObject() as? String {
                        print(filename)
                        if filename.hasSuffix("podspec.json") {
                            podSpecPath = "\(path)/\(filename)"
                            print("set podspecpath: \(podSpecPath)")
                        }
                        
                        if filename.lowercased().hasPrefix("\(version)/") && filename.hasSuffix("podspec.json"){
                            var newVersion = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"version\":", "\(path)/\(filename)"])
                            newVersion = newVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                            newVersion = newVersion.replacingOccurrences(of: "\"version\": ", with: "")
                            newVersion = newVersion.replacingOccurrences(of: "\"", with: "")
                            newVersion = newVersion.replacingOccurrences(of: ",", with: "")
                            
                            var tag = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"tag\":", "\(path)/\(filename)"])
                            tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                            tag = tag.replacingOccurrences(of: "\"version\": ", with: "")
                            tag = tag.replacingOccurrences(of: "\"", with: "")
                            tag = tag.replacingOccurrences(of: ",", with: "")
                            
                            let gitPath = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"git\":", "\(path)/\(filename)"])
                            
                            let libraryName = getNameFromGitPath(path: gitPath)
                            
                            if newVersion != "" && tag != "" {
                                translation.versions[version] = newVersion
                            }
                            
                            if var libraryName = libraryName {
                                libraryName = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                libraryName = libraryName.replacingOccurrences(of: "\"", with: "")
                                libraryName = libraryName.replacingOccurrences(of: ",", with: "")
                                
                                translation.name = libraryName
                            }
                            libraryDictionary[name] = translation
                            return (name: translation.name, version: newVersion)
                        }
                        
                        if let podSpecPath = podSpecPath {
                            print("parse podSpecPath: \(podSpecPath)")
                            var libraryName: String? = nil
                            
                            let gitPath = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"git\":", "\(podSpecPath)"])
                            print("found gitPath: \(gitPath)")
                            
                            libraryName = getNameFromGitPath(path: gitPath)
                            
                            if var libraryName = libraryName {
                                libraryName = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                libraryName = libraryName.replacingOccurrences(of: "\"", with: "")
                                libraryName = libraryName.replacingOccurrences(of: ",", with: "")
                                
                                translation.name = libraryName
                                libraryDictionary[name] = translation
                                
                                return (name: translation.name, version: nil)
                            }
                        }
                    }
                } else {
                    return nil // it was a null translation for speed purposes
                }
                
                return (name: translation.name, version: nil)
            }
        } else {
            //find library in specs
            let enumerator = FileManager.default.enumerator(atPath: specDirectory)
            while let filename = enumerator?.nextObject() as? String {
                //print(filename)
                if filename.lowercased().hasSuffix("/\(name)") {
                    print("found: \(filename)")
                    libraryDictionary[name] = (name: name, path: "\(specDirectory)/\(filename)", versions: [:])
                    return translateLibraryVersion(name: name, version: version)
                }
                
                if filename.count > 7 {
                    enumerator?.skipDescendents()
                }
            }
            
            libraryDictionary[name] = (name: name, path: nil, versions: [:]) // add null translation to speed up project analysis for projects that have many dependencies that cannot be found in cocoapods
        }
        /*
         cocoaPodsName:
            ( name:
              versions:
                [cocoaPodsVersion: tag]
            )
         */
        return nil
    }
    
    func analyseApp(folderPath: String) -> [Library] {
        //app.homePath
        
        var allLibraries: [Library] = []
        
        var dependencyFiles: [DependencyFile] = []
        dependencyFiles.append(findPodFile(homePath: folderPath))
        dependencyFiles.append(findCarthageFile(homePath: folderPath))
        dependencyFiles.append(findSwiftPMFile(homePath: folderPath))

        print("dependencyFiles: \(dependencyFiles)")
        
        for dependencyFile in dependencyFiles {
            if dependencyFile.used {
                if !dependencyFile.resolved {
                    print("Dependency \(dependencyFile.type) defined, but not resolved.")
                    continue
                }
                
                var libraries: [Library] = []
                if dependencyFile.type == .carthage {
                    libraries = handleCarthageFile(path: dependencyFile.resolvedFile!)
                } else if dependencyFile.type == .cocoapods {
                    libraries = handlePodsFile(path: dependencyFile.resolvedFile!)
                } else if dependencyFile.type == .swiftPM {
                    libraries = handleSwiftPmFile(path: dependencyFile.resolvedFile!)
                }
                
                allLibraries.append(contentsOf: libraries)
             }
        }
        
        return allLibraries
    }
    
    func handleCarthageFile(path: String) -> [Library] {
        print("handle carthage")
        var libraries: [Library] = []
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            
            for line in lines {
                let components = line.components(separatedBy: .whitespaces)
                print("components: \(components)")
                // components[0] = git, github
                
                if components.count != 3 {
                    break
                }
                
                let nameComponents = components[1].components(separatedBy: "/")
                
                var name: String
                if nameComponents.count >= 2 {
                    name = "\(nameComponents[nameComponents.count - 2])/\(nameComponents[nameComponents.count - 1])"
                } else {
                    name = components[1]
                }
                
                name = name.replacingOccurrences(of: "\"", with: "")
                
                if name.hasSuffix(".git") {
                    name = name.replacingOccurrences(of: ".git", with: "") // sometimes .git remanes behind name, must be removed
                }
                
                if name.hasPrefix("git@github.com:") {
                    name = name.replacingOccurrences(of: "git@github.com:", with: "") // for github projects, transform to regular username/projectname format
                }
                
                if name.hasPrefix("git@bitbucket.org:") { // for bitbucket projects keep bitbucket part to distinguish it
                    name = name.replacingOccurrences(of: "git@", with: "")
                    name = name.replacingOccurrences(of: ":", with: "/")
                }
                
                let version = components[2].replacingOccurrences(of: "\"", with: "")
                libraries.append(Library(name: name, versionString: version))
            }
        } catch {
            print("could not read carthage file \(path)")
        }
        
        return libraries
    }
    
    func handlePodsFile(path: String) -> [Library] {
        print("handle pods")
        var libraries: [Library] = []
        var declaredPods: [String] = []
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            print("lines: \(lines)")
            
            // at some point there was a change with intendations in
            
            var charactersBeforeDash = ""
            for line in lines {
                var chagnedLine = line
                chagnedLine = chagnedLine.trimmingCharacters(in: .whitespaces)
                
                if chagnedLine.starts(with: "PODS:") {
                    continue
                }
                
                if chagnedLine.starts(with: "-") {
                    charactersBeforeDash = line.components(separatedBy: "-")[0]
                    break
                }
                print("characters before dash: \(charactersBeforeDash)")
            }
            
            
            var reachedDependencies = false
            
            for fixedLine in lines {
                var line = fixedLine
                if line.starts(with: "DEPENDENCIES:") {
                    //break
                    reachedDependencies = true
                    continue
                }
                
                if reachedDependencies {
                    if line.starts(with: "\(charactersBeforeDash)- ") { // lines with more whitespace will be ignored
                        line = line.replacingOccurrences(of: "\(charactersBeforeDash)- ", with: "")
                        let components = line.components(separatedBy: .whitespaces)
                        var name = components[0].replacingOccurrences(of: "\"", with: "").lowercased()
                    
                        declaredPods.append(name)
                    }
                    
                    if line.trimmingCharacters(in: .whitespaces) == "" {
                        break
                    }
                    
                    if line.starts(with: "SPEC REPOS:") {
                        break
                    }
                }
            }
            
            print("declared pods: \(declaredPods)")
            
            for var line in lines {
                if line.starts(with: "DEPENDENCIES:") {
                    break
                }
                
                if line.starts(with: "PODS:") {
                    // ignore
                    continue
                }
                
                // check if direct or transitive?
                
                //line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.starts(with: "\(charactersBeforeDash)- ") { // lines with more whitespace will be ignored
                    line = line.lowercased()
                    line = line.replacingOccurrences(of: "\(charactersBeforeDash)- ", with: "")
                    let components = line.components(separatedBy: .whitespaces)
                    
                    print("components: \(components)")
                    
                    if(components.count < 2) {
                        continue
                    }
                    
                    var name = components[0].replacingOccurrences(of: "\"", with: "").lowercased()
                    name = name.replacingOccurrences(of: "'", with: "")
                    
                    var version = String(components[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    version = version.replacingOccurrences(of: ":", with: "")
                    version = version.replacingOccurrences(of: "\"", with: "")
                    version = String(version.dropLast().dropFirst())
                    //version.remove(at: version.startIndex) // remove (
                    //version.remove(at: version.endIndex) // remove )
                    
                    var direct = false
                    if declaredPods.contains(name) {
                        direct = true
                    }
                    
                    var subspec: String? = nil
                    if name.contains("/") {
                        var components = name.split(separator: "/")
                        name = String(components.removeFirst())
                        subspec = components.joined(separator: "/")
                    }
                    
                    // translate to same library names and versions as Carthage
                    if let translation = translateLibraryVersion(name: name, version: version) {
                        name = translation.name
                        if let translatedVersion = translation.version {
                            version = translatedVersion
                        }
                    }
                    
                    let library = Library(name: name, versionString: version)
                    library.directDependency = direct
                    library.subtarget = subspec
                    
                    libraries.append(library)
                    
                    print("save library, name: \(library.name), version: \(version)")
                } else {
                    // ignore
                    continue
                }
            }
        } catch {
            print("could not read pods file \(path)")
        }
        
        return libraries
    }
    
    func handleSwiftPmFile(path: String) -> [Library] {
        print("handle swiftpm")
        var libraries: [Library] = []
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let json = try JSONSerialization.jsonObject(with: data,
                                                          options: JSONSerialization.ReadingOptions.mutableContainers) as Any

            if let dictionary = json as? [String: Any] {
                if let object = dictionary["object"] as? [String: Any] {
                    if let pins = dictionary["pinds"] as? [[String: Any]] {
                        for pin in pins {
                            var name: String?
                            var version: String?
                            
                            name = pin["package"] as? String
                            
                            if let state = pin["state"] as? [String: Any] {
                                version = state["version"] as? String
                            }
                            
                            libraries.append(Library(name: name ?? "??", versionString: version ?? "??"))
                        }
                    }
                }
            }
        } catch {
            print("could not read swiftPM file \(path)")
        }
        
        return libraries
    }
    
    func findPodFile(homePath: String) -> DependencyFile {
        // find Podfile.lock
        
        /*
         PODS:
           - Alamofire (4.8.2) // we get name + version, what if multiple packages with the same name?
           - SwiftyJSON (5.0.0)

         DEPENDENCIES:
           - Alamofire
           - SwiftyJSON

         ....
         */
        
        
        
        let url = URL(fileURLWithPath: homePath)
        var definitionPath: String? = url.appendingPathComponent("Podfile").path
        var resolvedPath: String? = url.appendingPathComponent("Podfile.lock").path

        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: definitionPath!) {
            definitionPath = nil
        }
        
        if !fileManager.fileExists(atPath: resolvedPath!) {
            resolvedPath = nil
        }
        
        return DependencyFile(type: .cocoapods, file: definitionPath, resolvedFile: resolvedPath, definitionFile: definitionPath)
    }
    
    func findCarthageFile(homePath: String) -> DependencyFile {
        // find Carfile.resolved
        /*
         github "Alamofire/Alamofire" "4.7.3" // probably possible to add other kind of paths, not github? but we can start with just github --> gives us full path
         github "Quick/Nimble" "v7.1.3"
         github "Quick/Quick" "v1.3.1"
         github "SwiftyJSON/SwiftyJSON" "4.1.0"
         */
        let url = URL(fileURLWithPath: homePath)
        var definitionPath: String? = url.appendingPathComponent("Cartfile").path
        var resolvedPath: String? = url.appendingPathComponent("Cartfile.resolved").path
        
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: definitionPath!) {
            definitionPath = nil
        }
        
        if !fileManager.fileExists(atPath: resolvedPath!) {
            resolvedPath = nil
        }
        
        return DependencyFile(type: .carthage, file: definitionPath, resolvedFile: resolvedPath, definitionFile: definitionPath)
    }
    
    func findSwiftPMFile(homePath: String) -> DependencyFile{
        // Package.resolved
        /*
         {
           "object": {
             "pins": [
               {
                 "package": "Commandant", // we get package, repoURL, revision, version (more info that others!)
                 "repositoryURL": "https://github.com/Carthage/Commandant.git",
                 "state": {
                   "branch": null,
                   "revision": "2cd0210f897fe46c6ce42f52ccfa72b3bbb621a0",
                   "version": "0.16.0"
                 }
               },
            ....
            ]
          }
        }
         */
        
        let url = URL(fileURLWithPath: homePath)
        var definitionPath: String? = url.appendingPathComponent("Package.swift").path
        var resolvedPath: String? = url.appendingPathComponent("Package.resolved").path
        
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: definitionPath!) {
            definitionPath = nil
        }
        
        if !fileManager.fileExists(atPath: resolvedPath!) {
            resolvedPath = nil
        }
        
        return DependencyFile(type: .swiftPM, file: definitionPath, resolvedFile: resolvedPath, definitionFile: definitionPath)
    }
    
    enum DependencyType: String {
        case cocoapods, carthage, swiftPM
    }
    
    struct DependencyFile {
        let type: DependencyType
        let file: String?
        let resolvedFile: String?
        let definitionFile: String?
        
        var used: Bool {
            return file != nil
        }
        
        var resolved: Bool {
            return resolvedFile != nil
        }
    }
    
}

class Library {
    let name: String
    var subtarget: String?
    let versionString: String
    var directDependency: Bool? = nil
    
    init(name: String, versionString: String) {
        self.name = name.lowercased()
        self.versionString = versionString
    }
}
