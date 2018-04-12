//
//  HttpHandlers+WebSockets.swift
//  Swifter
//
//  Copyright © 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation


public func websocket(
      _ text: ((WebSocketSession, String) -> Void)?,
    _ binary: ((WebSocketSession, [UInt8]) -> Void)?) -> ((HttpRequest) -> HttpResponse) {
    return { r in
        guard r.hasTokenForHeader("upgrade", token: "websocket") else {
            return .badRequest(.text("Invalid value of 'Upgrade' header: \(r.headers["upgrade"])"))
        }
        guard r.hasTokenForHeader("connection", token: "upgrade") else {
            return .badRequest(.text("Invalid value of 'Connection' header: \(r.headers["connection"])"))
        }
        guard let secWebSocketKey = r.headers["sec-websocket-key"] else {
            return .badRequest(.text("Invalid value of 'Sec-Websocket-Key' header: \(r.headers["sec-websocket-key"])"))
        }
        let protocolSessionClosure: ((Socket) -> Void) = { socket in
            let session = WebSocketSession(socket)
            while let frame = try? session.readFrame() {
                switch frame.opcode {
                case .text:
                    if let handleText = text {
                        handleText(session, String.fromUInt8(frame.payload))
                    }
                case .binary:
                    if let handleBinary = binary {
                        handleBinary(session, frame.payload)
                    }
                default: break
                }
            }
        }
        let secWebSocketAccept = String.toBase64((secWebSocketKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").sha1())
        let headers = [ "Upgrade": "WebSocket", "Connection": "Upgrade", "Sec-WebSocket-Accept": secWebSocketAccept]
        return HttpResponse.switchProtocols(headers, protocolSessionClosure)
    }
}

public class WebSocketSession {
    
    public enum WebSocketError: Error { case unknownOpCode(String), unMaskedFrame }
    public enum OpCode: UInt8 { case `continue` = 0x00, close = 0x08, ping = 0x09, pong = 0x0A, text = 0x01, binary = 0x02 }
    
    public class Frame {
        public var opcode = OpCode.close
        public var fin = false
        public var payload = [UInt8]()
    }

    private let socket: Socket
    
    public init(_ socket: Socket) {
        self.socket = socket
    }
    
    public func writeText(_ text: String) -> Void {
        self.writeFrame(ArraySlice(text.utf8), OpCode.text)
    }

    public func writeBinary(_ binary: [UInt8]) -> Void {
        self.writeBinary(ArraySlice(binary))
    }
    
    public func writeBinary(_ binary: ArraySlice<UInt8>) -> Void {
        self.writeFrame(binary, OpCode.binary)
    }
    
    private func writeFrame(_ data: ArraySlice<UInt8>, _ op: OpCode, _ fin: Bool = true) {
        let finAndOpCode = UInt8(fin ? 0x80 : 0x00) | op.rawValue
        let maskAndLngth = encodeLengthAndMaskFlag(UInt64(data.count), false)
        do {
            try self.socket.writeUInt8([finAndOpCode])
            try self.socket.writeUInt8(maskAndLngth)
            try self.socket.writeUInt8(data)
        } catch {
            print(error)
        }
    }
    
    private func encodeLengthAndMaskFlag(_ len: UInt64, _ masked: Bool) -> [UInt8] {
        let encodedLngth = UInt8(masked ? 0x80 : 0x00)
        var encodedBytes = [UInt8]()
        switch len {
        case 0...125:
            encodedBytes.append(encodedLngth | UInt8(len));
        case 126...UInt64(UINT16_MAX):
            encodedBytes.append(encodedLngth | 0x7E);
            encodedBytes.append(UInt8(len >> 8));
            encodedBytes.append(UInt8(len & 0xFF));
        default:
            encodedBytes.append(encodedLngth | 0x7F);
            encodedBytes.append(UInt8(len >> 56) & 0xFF);
            encodedBytes.append(UInt8(len >> 48) & 0xFF);
            encodedBytes.append(UInt8(len >> 40) & 0xFF);
            encodedBytes.append(UInt8(len >> 32) & 0xFF);
            encodedBytes.append(UInt8(len >> 24) & 0xFF);
            encodedBytes.append(UInt8(len >> 16) & 0xFF);
            encodedBytes.append(UInt8(len >> 08) & 0xFF);
            encodedBytes.append(UInt8(len >> 00) & 0xFF);
        }
        return encodedBytes
    }
    
    public func readFrame() throws -> Frame {
        let frm = Frame()
        let fst = try socket.read()
        frm.fin = fst & 0x80 != 0
        let opc = fst & 0x0F
        guard let opcode = OpCode(rawValue: opc) else {
            // "If an unknown opcode is received, the receiving endpoint MUST _Fail the WebSocket Connection_."
            // http://tools.ietf.org/html/rfc6455#section-5.2 ( Page 29 )
            throw WebSocketError.unknownOpCode("\(opc)")
        }
        frm.opcode = opcode
        let sec = try socket.read()
        let msk = sec & 0x80 != 0
        guard msk else {
            // "...a client MUST mask all frames that it sends to the serve.."
            // http://tools.ietf.org/html/rfc6455#section-5.1
            throw WebSocketError.unMaskedFrame
        }
        var len = UInt64(sec & 0x7F)
        if len == 0x7E {
            let b0 = UInt64(try socket.read())
            let b1 = UInt64(try socket.read())
            len = UInt64(littleEndian: b0 << 8 | b1)
        } else if len == 0x7F {
            let b0 = UInt64(try socket.read())
            let b1 = UInt64(try socket.read())
            let b2 = UInt64(try socket.read())
            let b3 = UInt64(try socket.read())
            let b4 = UInt64(try socket.read())
            let b5 = UInt64(try socket.read())
            let b6 = UInt64(try socket.read())
            let b7 = UInt64(try socket.read())
            len = UInt64(littleEndian: b0 << 54 | b1 << 48 | b2 << 40 | b3 << 32 | b4 << 24 | b5 << 16 | b6 << 8 | b7)
        }
        let mask = [try socket.read(), try socket.read(), try socket.read(), try socket.read()]
        for i in 0..<len {
            frm.payload.append(try socket.read() ^ mask[Int(i % 4)])
        }
        return frm
    }
}
