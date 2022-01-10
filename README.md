# SwiftDependencyChecker

SwiftDependencyChecker can be installed with homebrew with the following commands:
    
    brew tap kristiinara/SwiftDependencyChecker
    brew install SwiftDependencyChecker
   
When installed SwiftDependencyChecker can be run as follows:
    
    SwiftDependencyChecker analyse --action all

This prints out info about vulnerable library versions used.

    SwiftDependencyChecker analyse --action sourceanalysis
prints out warnings related to use of vulnerable library versions in source files.

_Run script build phase_
Recommended usage is to add the following as a new “Run script” under “Build phases” in the Xcode project. Then output is displayed as warnings in Xcode. Using SwiftDependencyChecker this way makes it possible to automatically check for new vulnerabilities without any user interaction.
SwiftDependencyChecker analyse sourceanalysis
   
    SwiftDependencyChecker analyse --action sourceanalysis
    
Here is a blogpost with explanations of how the tool is built: https://medium.com/@kristiina_28701/swiftdependencychecker-check-cocoapods-carthage-and-swift-pm-dependencies-for-known-def2fba890c 
