//
//  Relfection.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

public protocol DatabaseReflectionProtocol {
    
    var id: UInt64? { get }
    
    init()
}

public class DatabaseReflection: DatabaseReflectionProtocol {
    
    static var sharedDatabase: SQLite?
    
    public var id: UInt64? = nil
    
    required public init() { }
}

public extension DatabaseReflectionProtocol {
    
    public func schemeWithValuesMethod2() -> (String, [String: Any?]) {
        let mirror = Mirror(reflecting: self)
        
        var fields = [String: Any?]()
        for case let (label?, value) in mirror.children {
            fields[label] = value
        }
        
        return ("\(mirror.subjectType)", fields)
    }
    
    public func schemeWithValuesAsString() -> (String, [(String, String?)]) {
        let (name, fields) = schemeWithValuesMethod2()
        var map = [(String, String?)]()
        for (key, value) in fields {
            // TODO - Replace this by extending all supported types by a protocol.
            // Example: 'extenstion Int: DatabaseConvertible { convert() -> something ( not necessary String type ) }'
            if let intValue    = value as? Int    { map.append((key, String(intValue))) }
            if let uintValue   = value as? UInt   { map.append((key, String(uintValue))) }
            if let int8Value   = value as? Int8   { map.append((key, String(int8Value))) }
            if let uint8Value  = value as? UInt8  { map.append((key, String(uint8Value))) }
            if let int16Value  = value as? Int16  { map.append((key, String(int16Value))) }
            if let uint16Value = value as? UInt16 { map.append((key, String(uint16Value))) }
            if let int32Value  = value as? Int32  { map.append((key, String(int32Value))) }
            if let uint32Value = value as? UInt32 { map.append((key, String(uint32Value))) }
            if let int64Value  = value as? Int64  { map.append((key, String(int64Value))) }
            if let uint64Value = value as? UInt64 { map.append((key, String(uint64Value))) }
            if let floatValue  = value as? Float  { map.append((key, String(floatValue))) }
            if let doubleValue = value as? Double { map.append((key, String(doubleValue))) }
            if let stringValue = value as? String { map.append((key, stringValue)) }
        }
        return (name, map)
    }
    
    public static func classInstanceWithSchemeMethod2() -> (Self, String, [String: Any?]) {
        let instance = Self()
        let (name, fields) = instance.schemeWithValuesMethod2()
        return (instance, name, fields)
    }
    
    static func find(_ id: UInt64) -> Self? {
        let (instance, _, _) = classInstanceWithSchemeMethod2()
        // TODO - make a query to DB
        return instance
    }
    
    public func insert() throws {
        guard let database = DatabaseReflection.sharedDatabase else {
            throw SQLiteError.openFailed("Database connection is not opened.")
        }
        let (name, fields) = schemeWithValuesAsString()
        try database.exec("CREATE TABLE IF NOT EXISTS \(name) (" + fields.map { "\($0.0) TEXT" }.joined(separator: ", ")  + ");")
        let names = fields.map { "\($0.0)" }.joined(separator: ", ")
        let values = Array(repeating: "?", count: fields.count).joined(separator: ", ")
        try database.exec("INSERT INTO \(name)(" + names + ") VALUES(" + values  + ");", fields.map { $0.1 })
    }
    
}

public func memoryLayoutForStructure(_ object: Any) -> [String: CountableRange<Int>] {
    var layout = [String: CountableRange<Int>]()
    var size = 0
    var alignment = 1
    for case let (label?, value) in Mirror(reflecting: object).children {
        var fieldLength = 0
        // TODO - Replace this with something smarter.
        if value is Int    { fieldLength = MemoryLayout<Int>.size   } else
        if value is UInt   { fieldLength = MemoryLayout<UInt>.size  } else
        if value is Int8   { fieldLength = MemoryLayout<Int8>.size  } else
        if value is UInt8  { fieldLength = MemoryLayout<UInt8>.size } else
        if value is Int16  { fieldLength = MemoryLayout<Int16>.size } else
        if value is UInt16 { fieldLength = MemoryLayout<UInt16>.size} else
        if value is Int32  { fieldLength = MemoryLayout<Int32>.size } else
        if value is UInt32 { fieldLength = MemoryLayout<UInt32>.size} else
        if value is Int64  { fieldLength = MemoryLayout<Int64>.size } else
        if value is UInt64 { fieldLength = MemoryLayout<UInt64>.size} else
        if value is Float  { fieldLength = MemoryLayout<Float>.size } else
        if value is Double { fieldLength = MemoryLayout<Double>.size} else
        if value is String { fieldLength = MemoryLayout<String>.size}
        if fieldLength <= alignment {
            layout[label] = size ..< size + fieldLength
            size = size + fieldLength
            alignment = fieldLength
        } else {
            let offset = size + (fieldLength > size ? (fieldLength - size) : (size % fieldLength))
            layout[label] = offset ..< offset + fieldLength
            size = offset + fieldLength
            alignment = fieldLength
        }
    }
    return layout
}
