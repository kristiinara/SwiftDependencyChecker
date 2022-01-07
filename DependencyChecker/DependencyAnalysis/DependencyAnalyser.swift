//
//  DependencyAnalyser.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 01.01.2022.
//
import Foundation
import os.log

class DependencyAnalyser {
    var translations: Translations
    var url: URL
    var folder: URL
    var changed = false
    let settings: Settings
    let specDirectory: String
    var onlyDirectDependencies = false
    
    init(settings: Settings) {
        self.folder = settings.homeFolder
        self.url = self.folder.appendingPathComponent("translation.json")
        
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(Translations.self, from: data) {
                translations = decoded
            } else {
                translations = Translations(lastUpdated: Date(), translations: [:])
            }
        } else {
            translations = Translations(lastUpdated: Date(), translations: [:])
        }
        self.settings = settings
        self.specDirectory = settings.specDirectory.path
        
        if self.checkSpecDirectory() == false {
            self.checkoutSpecDirectory()
        }
        
        if self.shouldUpdate {
            self.update()
        }
    }
    
    var shouldUpdate: Bool {
        os_log("last updated: \(self.translations.lastUpdated)")
        
        if let timeInterval = self.settings.specTranslationTimeInterval {
            // check if time since last updated is larger than the allowed timeinterval for updates
            if self.translations.lastUpdated.timeIntervalSinceNow * -1 > timeInterval {
                os_log("Will update")
                return true
            }
        }
        
        os_log("No update")
        return false
    }
    
    func update() {
        os_log("update spec directory")
        self.updateSpecDirectory()
        var updatedTranslations: [String: Translation] = [:]
        
        for translation in self.translations.translations {
            if translation.value.noTranslation {
                // ignore, these will be removed from translations so that they can be updated
            } else {
                updatedTranslations[translation.key] = translation.value
            }
        }
        self.translations.lastUpdated = Date()
        self.translations.translations = updatedTranslations
        
        self.changed = true
    }
    
    func checkSpecDirectory() -> Bool{
        let directory = self.settings.specDirectory
        let specPath = directory.appendingPathComponent("Specs", isDirectory: true)
        
        os_log("check spec path: \(specPath.path)")
        let pathExists = FileManager.default.fileExists(atPath: specPath.path)
        os_log("path exists: \(pathExists)")
        
        return pathExists
    }
    
    func checkoutSpecDirectory() {
        let source = "https://github.com/CocoaPods/Specs.git"
        let directory = self.specDirectory
        os_log("checkout spec directory into \(directory)")
        
        let res = Helper.shell(launchPath: "/usr/bin/git", arguments: ["clone", source, directory])
            
        os_log("Git clone.. \(res)")
    }
    
    func updateSpecDirectory() {
        os_log("update spec directory")
        let directory = self.specDirectory
        let gitPath = "\(directory)/.git"
        
        let res = Helper.shell(launchPath: "/usr/bin/git", arguments: ["--git-dir", gitPath, "--work-tree", directory, "pull"])
        os_log("Git pull.. \(res)")
    }
    
    deinit {
        if changed {
            save()
        }
    }
    
    func checkFolder() {
        if !FileManager.default.fileExists(atPath: self.folder.absoluteString) {
            do {
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                os_log("Could not create folder: \(self.folder)")
            }
        }
    }
    
    func save() {
        self.checkFolder()
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(translations) {
            do {
                try encoded.write(to: url)
            } catch {
                os_log("Could not save translations")
            }
        }
    }
    
    func saveLibraries(path: String, libraries: [Library]) {
        self.checkFolder()
        
        let projectsUrl = self.folder.appendingPathComponent("projects.json")
        var projects: Projects? = nil
        
        if let data = try? Data(contentsOf: projectsUrl) {
            let decoder = JSONDecoder()
            if let decoded = try? decoder.decode(Projects.self, from: data) {
                projects = decoded
            }
        }
        
        if projects == nil{
            projects = Projects()
        }
        
        projects?.usedLibraries[path] = libraries
        
        if let projects = projects {
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(projects) {
                do {
                    try encoded.write(to: projectsUrl)
                } catch {
                    os_log("Could not save projects")
                }
            }
        }
        
        
    }
    
    //libraryDictionary: [String: (name: String, path: String?, versions: [String:String])] = [:]
    
    
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
            foundName = foundName.trimmingCharacters(in: .whitespacesAndNewlines)
            foundName = foundName.replacingOccurrences(of: "\"", with: "")
            foundName = foundName.replacingOccurrences(of: ",", with: "")
            
            libraryName = foundName
        }
        
        return libraryName
    }
        
    func translateLibraryVersion(name: String, version: String) -> (name: String, module: String?, version: String?)? {
        os_log("translate library name: \(name), version: \(version)")
        
        let specSubPath = "\(self.specDirectory)/Specs"
        
        if let translation = self.translations.translations[name] {
            if translation.noTranslation {
                return nil
            }
            
            if let translatedVersion = translation.translatedVersions[version] {
                if let libraryName = translation.libraryName {
                    return (name:libraryName, module: translation.moduleName, version: translatedVersion)
                } else {
                    return nil
                }
                
            } else {
                if let path = translation.specFolderPath {
                    let enumerator = FileManager.default.enumerator(atPath: path)
                    var podSpecPath: String? = nil
                    while let filename = enumerator?.nextObject() as? String {
                        os_log("\(filename)")
                        if filename.hasSuffix("podspec.json") {
                            podSpecPath = "\(path)/\(filename)"
                            os_log("\(podSpecPath!)")
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
                            
                            
                            var moduleString = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"module_name\":", "\(path)/\(filename)"])
                            moduleString = moduleString.trimmingCharacters(in: .whitespacesAndNewlines)
                            moduleString = moduleString.replacingOccurrences(of: "\"module_name\": ", with: "")
                            moduleString = moduleString.replacingOccurrences(of: "\"", with: "")
                            moduleString = moduleString.replacingOccurrences(of: ",", with: "")
                            print("moduleString: \(moduleString)")
                            
                            var module: String?
                            if moduleString == "" {
                                module = nil
                            } else {
                                module = moduleString
                            }
 
                            let gitPath = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"git\":", "\(path)/\(filename)"])
                            
                            var libraryName = getNameFromGitPath(path: gitPath)
                            
                            if newVersion != "" && tag != "" {
                                translation.translatedVersions[version] = newVersion
                            }
                            
                            if let newLibraryName = libraryName {
                                libraryName = newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                                libraryName = newLibraryName.replacingOccurrences(of: "\"", with: "")
                                libraryName = newLibraryName.replacingOccurrences(of: ",", with: "")
                                
                                libraryName = newLibraryName
                            }
                            
                            translation.libraryName = libraryName
                            translation.moduleName = module
                            self.translations.translations[name] = translation
                            self.changed = true
                            
                            if let libraryName = libraryName {
                                return (name: libraryName, module: module, version: newVersion)
                            } else {
                                return nil
                            }
                        }
                    }
                    if let podSpecPath = podSpecPath {
                        os_log("parse podSpecPath: \(podSpecPath)")
                        var libraryName: String? = nil
                        
                        let gitPath = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"git\":", "\(podSpecPath)"])
                        os_log("found gitPath: \(gitPath)")
                        
                        libraryName = getNameFromGitPath(path: gitPath)
                        
                        var moduleString = Helper.shell(launchPath: "/usr/bin/grep", arguments: ["\"module_name\":", "\(podSpecPath)"])
                        moduleString = moduleString.trimmingCharacters(in: .whitespacesAndNewlines)
                        moduleString = moduleString.replacingOccurrences(of: "\"module_name\": ", with: "")
                        moduleString = moduleString.replacingOccurrences(of: "\"", with: "")
                        moduleString = moduleString.replacingOccurrences(of: ",", with: "")
                        print("moduleString: \(moduleString)")
                        
                        var module: String?
                        if moduleString == "" {
                            module = nil
                        } else {
                            module = moduleString
                        }
                        
                        if var libraryName = libraryName {
                            libraryName = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            libraryName = libraryName.replacingOccurrences(of: "\"", with: "")
                            libraryName = libraryName.replacingOccurrences(of: ",", with: "")
                            
                            translation.libraryName = libraryName
                            translation.moduleName = module
                            self.translations.translations[name] = translation
                            self.changed = true
                            
                            return (name: libraryName, module: module, version: nil)
                        }
                    }
                } else {
                    return nil // it was a null translation for speed purposes
                }
                
                if let libraryName = translation.libraryName {
                    return (name: libraryName, module: translation.moduleName, version: nil)
                }
            }
        } else {
            os_log("specpath: \(specSubPath)")
            //find library in specs
            let enumerator = FileManager.default.enumerator(atPath: specSubPath)
            while let filename = enumerator?.nextObject() as? String {
                os_log("\(filename), looking for \(name)")
                if filename.lowercased().hasSuffix("/\(name)") {
                    os_log("found: \(filename)")
                    
                    let translation = Translation(podspecName: name)
                    translation.specFolderPath = "\(specSubPath)/\(filename)"
                    translations.translations[name] = translation
                    self.changed = true
                    
                    return translateLibraryVersion(name: name, version: version)
                }
                
                if filename.count > 7 && !filename.hasSuffix(".DS_Store") {
                    enumerator?.skipDescendents()
                }
            }
            
            let translation = Translation(podspecName: name)
            translation.noTranslation = true
            self.translations.translations[name] = translation
            self.changed = true
            // add null translation to speed up project analysis for projects that have many dependencies that cannot be found in cocoapods
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

        os_log("dependencyFiles: \(dependencyFiles)")
        
        for dependencyFile in dependencyFiles {
            if dependencyFile.used {
                if !dependencyFile.resolved {
                    os_log("Dependency \(dependencyFile.type.rawValue) defined, but not resolved.")
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
        
        self.saveLibraries(path: folderPath, libraries: allLibraries)
        
        return allLibraries
    }
    
    func handleCarthageFile(path: String) -> [Library] {
        os_log("handle carthage")
        var libraries: [Library] = []
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            
            for line in lines {
                let components = line.components(separatedBy: .whitespaces)
                os_log("components: \(components)")
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
                
                let library = Library(name: name, versionString: version)
                library.platform = "carthage"
                
                libraries.append(library)
            }
        } catch {
            os_log("could not read carthage file \(path)")
        }
        
        return libraries
    }
    
    func handlePodsFile(path: String) -> [Library] {
        os_log("handle pods")
        var libraries: [Library] = []
        var declaredPods: [String] = []
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            os_log("lines: \(lines)")
            
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
                os_log("characters before dash: \(charactersBeforeDash)")
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
                        let name = components[0].replacingOccurrences(of: "\"", with: "").lowercased()
                    
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
            
            os_log("declared pods: \(declaredPods)")
            
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
                    
                    os_log("components: \(components)")
                    
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
                    
                    if direct == false && self.onlyDirectDependencies {
                        continue // ignore indirect dependencies
                    }
                    
                    var subspec: String? = nil
                    if name.contains("/") {
                        var components = name.split(separator: "/")
                        name = String(components.removeFirst())
                        subspec = components.joined(separator: "/")
                    }
                    
                    var module: String? = nil
                    // translate to same library names and versions as Carthage
                    if let translation = translateLibraryVersion(name: name, version: version) {
                        name = translation.name
                        if let translatedVersion = translation.version {
                            version = translatedVersion
                        }
                        module = translation.module
                    }
                    
                    let library = Library(name: name, versionString: version)
                    library.directDependency = direct
                    library.subtarget = subspec
                    library.module = module
                    library.platform = "cocoapods"
                    
                    libraries.append(library)
                    
                    os_log("save library, name: \(library.name), version: \(version)")
                } else {
                    // ignore
                    continue
                }
            }
        } catch {
            os_log("could not read pods file \(path)")
        }
        
        return libraries
    }
    
    func handleSwiftPmFile(path: String) -> [Library] {
        os_log("handle swiftpm")
        var libraries: [Library] = []
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let json = try JSONSerialization.jsonObject(with: data,
                                                          options: JSONSerialization.ReadingOptions.mutableContainers) as Any

            if let dictionary = json as? [String: Any] {
                if let object = dictionary["object"] as? [String: Any] {
                    if let pins = object["pins"] as? [[String: Any]] {
                        for pin in pins {
                            var name: String?
                            var version: String?
                            
                            name = pin["package"] as? String
                            
                            if let state = pin["state"] as? [String: Any] {
                                version = state["version"] as? String
                            }
                            
                            let library = Library(name: name ?? "??", versionString: version ?? "??")
                            library.platform = "swiftpm"
                            
                            libraries.append(library)
                        }
                    }
                }
            }
        } catch {
            os_log("could not read swiftPM file \(path)")
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

class Translations: Codable {
    var lastUpdated: Date
    var translations: [String: Translation]
    
    init(lastUpdated: Date, translations: [String: Translation]) {
        self.lastUpdated = lastUpdated
        self.translations = translations
    }
}

class Translation: Codable {
    var podspecName: String
    var gitPath: String?
    var libraryName: String?
    var moduleName: String?
    var specFolderPath: String?
    var translatedVersions: [String:String] = [:]
    var noTranslation: Bool = false
    
    init(podspecName: String) {
        self.podspecName = podspecName
    }
}

class Projects: Codable {
    var usedLibraries: [String: [Library]] = [:]
}

class Library: Codable {
    let name: String
    var subtarget: String?
    let versionString: String
    var directDependency: Bool? = nil
    var module: String?
    var platform: String?
    
    init(name: String, versionString: String) {
        self.name = name.lowercased()
        self.versionString = versionString
    }
}
