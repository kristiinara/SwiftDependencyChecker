//
//  File.swift
//  
//
//  Created by Kristiina Rahkema on 17.01.2022.
//

import Foundation

class Logger {
    enum Level: Int {
        case debug = 0, info, error, none
    }
    
    static var setLevel: Level = .info
    
    static func log(_ level: Level, _ message: String) {
        if setLevel != .none && level.rawValue >= setLevel.rawValue {
            print(message)
        }
    }
    
}
