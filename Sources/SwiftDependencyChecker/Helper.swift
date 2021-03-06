//
//  Helper.swift
//  DependencyChecker
//
//  Created by Kristiina Rahkema on 01.01.2022.
//

import Foundation

class Helper {
    static func shell(launchPath path: String, arguments args: [String]) -> String {
        Logger.log(.debug, "[*] Running Helper.shell for path \(path), arguments: \(args)")
        var output = shellOptinal(launchPath: path, arguments: args)
        
        if let output = output {
            return output
        }
        
        // domething failed, try again once!
        output = shellOptinal(launchPath: path, arguments: args)
        
        if let output = output {
            Logger.log(.debug, "[i] Helper.shell output: \(output)")
            return output
        }
        
        Logger.log(.debug, "[i] Helper.shell did not return anything")
        return ""
    }
    
    static func shellOptinal(launchPath path: String, arguments args: [String]) -> String? {
        Logger.log(.debug, "[*] Running Helper.shellOptional for path \(path), arguments: \(args)")
        
        var output: String? = nil
        
        autoreleasepool {
            let task = Process()
            task.launchPath = path
            task.arguments = args
            
            if var environment = task.environment {
                environment["GIT_TERMINAL_PROMPT"] = "0"
                task.environment = environment
            } else {
                task.environment = ["GIT_TERMINAL_PROMPT": "0"]
            }

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.launch()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            output = String(data: data, encoding: .utf8)
            task.waitUntilExit()
        }

        return(output)
    }
    
    static func shellAsync(launchPath path: String, arguments args: [String], completion: @escaping ((String, Bool) -> Void )){
        Logger.log(.debug, "[*] Running Helper.shellAsync for path \(path), arguments: \(args)")
        autoreleasepool {
            let task = Process()
            task.launchPath = path
            task.arguments = args

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            
            task.terminationHandler = { returnedTask in

                    let status = returnedTask.terminationStatus
                    if status == 0 {
                       completion("", true)
                    } else {
                        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data:errorData, encoding: .utf8)!
                        completion(errorString, true)
                    }
                }
                let outputHandle = (task.standardOutput as! Pipe).fileHandleForReading
                NotificationCenter.default.addObserver(forName: FileHandle.readCompletionNotification, object: outputHandle, queue: OperationQueue.current, using: { notification in
                    if let data = notification.userInfo?[NSFileHandleNotificationDataItem] as? Data, !data.isEmpty {
                        completion(String(data: data, encoding: . utf8)!, false)
                    } else {
                        task.terminate()
                        return
                    }
                    outputHandle.readInBackgroundAndNotify()
                })
                outputHandle.readInBackgroundAndNotify()
                task.launch()
        }
    }
}
