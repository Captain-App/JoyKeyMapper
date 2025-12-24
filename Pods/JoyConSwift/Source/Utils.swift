//
//  Utils.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation

func ReadInt16(from ptr: UnsafePointer<UInt8>) -> Int16 {
    var val: Int16 = 0
    memcpy(&val, ptr, MemoryLayout<Int16>.size)
    return val
}

func ReadUInt16(from ptr: UnsafePointer<UInt8>) -> UInt16 {
    var val: UInt16 = 0
    memcpy(&val, ptr, MemoryLayout<UInt16>.size)
    return val
}

func ReadInt32(from ptr: UnsafePointer<UInt8>) -> Int32 {
    var val: Int32 = 0
    memcpy(&val, ptr, MemoryLayout<Int32>.size)
    return val
}

func ReadUInt32(from ptr: UnsafePointer<UInt8>) -> UInt32 {
    var val: UInt32 = 0
    memcpy(&val, ptr, MemoryLayout<UInt32>.size)
    return val
}
