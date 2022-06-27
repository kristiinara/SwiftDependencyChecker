//
//  DependencyAnalyser.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 01.01.2022.
//
import Foundation

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
        Logger.log(.info, "[i] Translations last updated: \(self.translations.lastUpdated)")
        
        if let timeInterval = self.settings.specTranslationTimeInterval {
            // check if time since last updated is larger than the allowed timeinterval for updates
            if self.translations.lastUpdated.timeIntervalSinceNow * -1 > timeInterval {
                Logger.log(.info, "[i] Will update spec data")
                return true
            }
        }
        
        Logger.log(.info, "[i] No update for spec data")
        return false
    }
    
    func update() {
        Logger.log(.info, "[*] Updating spec directory ...")
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
        
        Logger.log(.debug, "[*] Checking spec path: \(specPath.path)")
        let pathExists = FileManager.default.fileExists(atPath: specPath.path)
        Logger.log(.debug, "[i] path exists: \(pathExists)")
        
        return pathExists
    }
    
    func checkoutSpecDirectory() {
        let source = "https://github.com/CocoaPods/Specs.git"
        let directory = self.specDirectory
        Logger.log(.info, "[*] Checking out spec directory into \(directory)")
        
        let res = Helper.shell(launchPath: "/usr/bin/git", arguments: ["clone", source, directory])
            
        Logger.log(.debug, "[i] Git clone.. \(res)")
    }
    
    func updateSpecDirectory() {
        Logger.log(.debug, "[*] Updating spec directory ...")
        let directory = self.specDirectory
        let gitPath = "\(directory)/.git"
        
        let res = Helper.shell(launchPath: "/usr/bin/git", arguments: ["--git-dir", gitPath, "--work-tree", directory, "pull"])
        Logger.log(.debug, "[i] Git pull.. \(res)")
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
                Logger.log(.error, "[!] Could not create folder: \(self.folder)")
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
                Logger.log(.error, "[!] Could not save translations")
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
                    Logger.log(.error, "[!] Could not save projects")
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
        Logger.log(.debug, "[*] Translating library name: \(name), version: \(version) ...")
        
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
                        Logger.log(.debug, "[*] Checking file \(filename)")
                        if filename.hasSuffix("podspec.json") {
                            podSpecPath = "\(path)/\(filename)"
                            Logger.log(.debug, "[i] Is podspec: \(podSpecPath!)")
                        }
                        
                        if filename.lowercased().hasPrefix("\(version)/") && filename.hasSuffix("podspec.json"){
                            Logger.log(.debug, "[*] Fetching info from file ...")
                            
                            let values = findValuesInPodspecFile(keys: ["tag", "module_name", "git"], path: "\(path)/\(filename)")
                            
                            var tag = values["tag"]
                            var module = values["module_name"]
                            let gitPath = values["git"] ?? ""
                            Logger.log(.debug, "[i] Found gitPath: \(gitPath)")
                            Logger.log(.debug, "[i] Found module: \(module)")
                            Logger.log(.debug, "[i] Found tag: \(tag)")
                            
                            var libraryName = getNameFromGitPath(path: gitPath)
                            
                            if tag != nil && tag != "" {
                                translation.translatedVersions[version] = tag
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
                                Logger.log(.debug, "[i] Translation with name and version.")
                                return (name: libraryName, module: module, version: translation.translatedVersions[version])
                            } else {
                                return nil
                            }
                        }
                    }
                    if let podSpecPath = podSpecPath {
                        Logger.log(.debug, "[*] Fetching info from podSpecPath: \(podSpecPath)")
                        var libraryName: String? = nil
                        
                        let values = findValuesInPodspecFile(keys: ["module_name", "git"], path: podSpecPath)
                        
                        let gitPath = values["git"] ?? ""
                        Logger.log(.debug, "[i] Found gitPath: \(gitPath)")
                        
                        libraryName = getNameFromGitPath(path: gitPath)
                        
                        var module = values["module_name"]
                        Logger.log(.debug, "[i] Found moduleString: \(module ?? "")")
                        
                        if var libraryName = libraryName {
                            libraryName = libraryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            libraryName = libraryName.replacingOccurrences(of: "\"", with: "")
                            libraryName = libraryName.replacingOccurrences(of: ",", with: "")
                            
                            translation.libraryName = libraryName
                            translation.moduleName = module
                            self.translations.translations[name] = translation
                            self.changed = true
                            
                            Logger.log(.debug, "[i] Translation with no version")
                            return (name: libraryName, module: module, version: nil)
                        }
                    }
                } else {
                    Logger.log(.debug, "[i] Null translation from dictionary")
                    return nil // it was a null translation for speed purposes
                }
                
                if let libraryName = translation.libraryName {
                    Logger.log(.debug, "[i] Translation with no version from dictionary.")
                    return (name: libraryName, module: translation.moduleName, version: nil)
                }
            }
        } else {
            Logger.log(.debug, "[*] Analysing spec sub path: \(specSubPath)")
            //find library in specs
            let enumerator = FileManager.default.enumerator(atPath: specSubPath)
            while let filename = enumerator?.nextObject() as? String {
                if filename.lowercased().hasSuffix("/\(name)") {
                    Logger.log(.debug, "[i] Found file: \(filename)")
                    
                    let translation = Translation(podspecName: name)
                    translation.specFolderPath = "\(specSubPath)/\(filename)"
                    translations.translations[name] = translation
                    self.changed = true
                    
                    Logger.log(.debug, "[*] Saving translation with podspec sub path and running translate again ...")
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
        
        let translation = Translation(podspecName: name)
        translation.noTranslation = true
        self.translations.translations[name] = translation
        self.changed = true
        
        Logger.log(.debug, "[i] No translation found, saving and returning nil.")
        return nil
    }
    
    func findValuesInPodspecFile(keys: [String], path: String) -> [String: String] {
        var dictionary: [String: String] = [:]
        
        if let fileContents = try? String(contentsOfFile: path) {
            let lines = fileContents.components(separatedBy: .newlines)
            
            for key in keys {
                for var line in lines {
                    line = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.hasPrefix("\"\(key)\": ") {
                        var value = line
                        
                        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        value = value.replacingOccurrences(of: "\"\(key)\": ", with: "")
                        value = value.replacingOccurrences(of: "\"", with: "")
                        value = value.replacingOccurrences(of: ",", with: "")
                        
                        dictionary[key] = value
                        break
                    }
                }
            }
        } else {
            Logger.log(.error, "[!] Could not read spec file at: \(path)")
        }
        
        return dictionary
    }
    
    func analyseApp(folderPath: String) -> [Library] {
        //app.homePath
        
        var allLibraries: [Library] = []
        
        var dependencyFiles: [DependencyFile] = []
        dependencyFiles.append(findPodFile(homePath: folderPath))
        dependencyFiles.append(findCarthageFile(homePath: folderPath))
        dependencyFiles.append(findSwiftPMFile(homePath: folderPath))

        Logger.log(.debug, "[*] Analysing dependency files for \(folderPath): \(dependencyFiles.count) files found ...")
        
        for dependencyFile in dependencyFiles {
            if dependencyFile.used {
                if !dependencyFile.resolved {
                    Logger.log(.debug, "[i] Dependency \(dependencyFile.type.rawValue) defined, but not resolved.")
                    continue
                }
            }
            
            if dependencyFile.resolved {
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
        Logger.log(.debug, "[*] Parsing Carthage resolution file \(path)")
        var libraries: [Library] = []
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            
            for line in lines {
                let components = line.components(separatedBy: .whitespaces)
                Logger.log(.debug, "[i] Dependency components: \(components)")
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
                Logger.log(.debug, "Found library: \(name), version: \(version)")
                
                libraries.append(library)
            }
        } catch {
            Logger.log(.error, "[!] Could not read carthage file \(path)")
        }
        
        return libraries
    }
    
    func handlePodsFile(path: String) -> [Library] {
        Logger.log(.debug, "[*] Parsing CoocaPods resolution file \(path) ...")
        var libraries: [Library] = []
        var declaredPods: [String] = []
        do {
            let data = try String(contentsOfFile: path, encoding: .utf8)
            let lines = data.components(separatedBy: .newlines)
            Logger.log(.debug, "[i] Lines: \(lines)")
            
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
                Logger.log(.debug, "[i] Characters before dash: \(charactersBeforeDash)")
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
            
            Logger.log(.debug, "[i] Declared pods: \(declaredPods)")
            
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
                    
                    Logger.log(.debug, "components: \(components)")
                    
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
                    var oldName = name
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
                    
                    if let module = module {
                        library.module = module
                    } else {
                        library.module = oldName
                    }
                    library.platform = "cocoapods"
                    
                    libraries.append(library)
                    
                    Logger.log(.debug, "[*] Saving library, name: \(library.name), version: \(version)")
                } else {
                    // ignore
                    continue
                }
            }
        } catch {
            Logger.log(.error, "[!] Could not read pods file \(path)")
        }
        
        return libraries
    }
    
    func handleSwiftPmFile(path: String) -> [Library] {
        Logger.log(.debug, "[*] Parsing Swift PM resolution file \(path) ...")
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
                            var module: String?
                            
                            module = pin["package"] as? String
                            let repoURL = pin["repositoryURL"] as? String
                            
                            if let url = repoURL {
                                if let correctName = getNameFrom(url: url) {
                                    name = correctName
                                } else {
                                    name = module
                                }
                            } else {
                                name = module
                            }
                            
                            
                            if let state = pin["state"] as? [String: Any] {
                                version = state["version"] as? String
                            }
                            
                            let library = Library(name: name ?? "??", versionString: version ?? "")
                            library.platform = "swiftpm"
                            library.module = module
                            Logger.log(.debug, "[i] Found library name: \(name), version: \(version)")
                            
                            libraries.append(library)
                        }
                    }
                }
            }
        } catch {
            Logger.log(.error, "[!] Could not read swiftPM file \(path)")
        }
        
        return libraries
    }
    
    func getNameFrom(url: String) -> String? {
        let value = url.replacingOccurrences(of: ".git", with: "")
        let components = value.split(separator: "/")
        if components.count < 2 {
            return nil
        }
        
        let count = components.count
        let name = "\(components[count - 2])/\(components[count - 1])"
        return name
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
            
            
            if let resolvedInProject = findPackageResolved(path: homePath) {
                resolvedPath = resolvedInProject
                print("Found path: \(resolvedPath)")
            }
        }
        
        return DependencyFile(type: .swiftPM, file: definitionPath, resolvedFile: resolvedPath, definitionFile: definitionPath)
    }
    
    func findPackageResolved(path: String) -> String? {
     // TestApp.xcodeproj % grep -rni "AFNetworking" *
        // project.xcworkspace/xcshareddata/swiftpm/Package.resolved:5:        "package": "AFNetworking",
        
        print("Try to find resolved path in home: \(path)")
        
        let enumerator = FileManager.default.enumerator(atPath: path)
        
        var resolvedPath: String?
        
        while let filename = enumerator?.nextObject() as? String {
            if filename.hasSuffix(".xcodeproj") {
                let composedPath = "\(path)/\(filename)/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
                
                if FileManager.default.fileExists(atPath: composedPath) {
                    resolvedPath = composedPath
                    break
                }
                
                enumerator?.skipDescendents()
            }
        }
        
        return resolvedPath
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
