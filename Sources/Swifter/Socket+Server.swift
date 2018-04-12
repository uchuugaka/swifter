//
//  Socket+Server.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

#if os(Linux)
    import Glibc
#else
    import Foundation
#endif

extension Socket {
    
    public class func tcpSocketForListen(_ port: in_port_t, _ forceIPv4: Bool = false, _ maxPendingConnection: Int32 = SOMAXCONN) throws -> Socket {
        
        #if os(Linux)
            let socketFileDescriptor = socket(forceIPv4 ? AF_INET : AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
        #else
            let socketFileDescriptor = socket(forceIPv4 ? AF_INET : AF_INET6, SOCK_STREAM, 0)
        #endif
        
        if socketFileDescriptor == -1 {
            throw SocketError.socketCreationFailed(Process.lastErrno)
        }
        
        var value: Int32 = 1
        if setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size)) == -1 {
            let details = Process.lastErrno
            Socket.release(socketFileDescriptor)
            throw SocketError.socketSettingReUseAddrFailed(details)
        }
        Socket.setNoSigPipe(socketFileDescriptor)
        
        #if os(Linux)
            var bindResult: Int32 = -1
            if forceIPv4 {
                var addr = sockaddr_in(sin_family: sa_family_t(AF_INET),
                                       sin_port: port.bigEndian,
                                       sin_addr: in_addr(s_addr: in_addr_t(0)),
                                       sin_zero:(0, 0, 0, 0, 0, 0, 0, 0))
                
                bindResult = withUnsafePointer(&addr) {
                    bind(socketFileDescriptor, UnsafePointer<sockaddr>($0), socklen_t(sizeof(sockaddr_in)))
                }
            } else {
                var addr = sockaddr_in6(sin6_family: sa_family_t(AF_INET6),
                                        sin6_port: port.bigEndian,
                                        sin6_flowinfo: 0,
                                        sin6_addr: in6addr_any,
                                        sin6_scope_id: 0)
                
                bindResult = withUnsafePointer(&addr) {
                    bind(socketFileDescriptor, UnsafePointer<sockaddr>($0), socklen_t(sizeof(sockaddr_in6)))
                }
            }
        #else
            var bindResult: Int32 = -1
            if forceIPv4 {
                var addr = sockaddr_in(sin_len: UInt8(MemoryLayout<sockaddr_in>.stride),
                                       sin_family: UInt8(AF_INET),
                                       sin_port: port.bigEndian,
                                       sin_addr: in_addr(s_addr: in_addr_t(0)),
                                       sin_zero:(0, 0, 0, 0, 0, 0, 0, 0))
                
                bindResult = withUnsafePointer(to: &addr) {
                    bind(socketFileDescriptor, UnsafePointer<sockaddr>(OpaquePointer($0)), socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            } else {
                var addr = sockaddr_in6(sin6_len: UInt8(MemoryLayout<sockaddr_in6>.stride),
                                        sin6_family: UInt8(AF_INET6),
                                        sin6_port: port.bigEndian,
                                        sin6_flowinfo: 0,
                                        sin6_addr: in6addr_any,
                                        sin6_scope_id: 0)
                
                bindResult = withUnsafePointer(to: &addr) {
                    bind(socketFileDescriptor, UnsafePointer<sockaddr>(OpaquePointer($0)), socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        #endif
        
        if bindResult == -1 {
            let details = Process.lastErrno
            Socket.release(socketFileDescriptor)
            throw SocketError.bindFailed(details)
        }
        
        if listen(socketFileDescriptor, maxPendingConnection) == -1 {
            let details = Process.lastErrno
            Socket.release(socketFileDescriptor)
            throw SocketError.listenFailed(details)
        }
        return Socket(socketFileDescriptor: socketFileDescriptor)
    }
    
    public func acceptClientSocket() throws -> Socket {
        var addr = sockaddr()
        var len: socklen_t = 0
        let clientSocket = accept(self.socketFileDescriptor, &addr, &len)
        if clientSocket == -1 {
            throw SocketError.acceptFailed(Process.lastErrno)
        }
        Socket.setNoSigPipe(clientSocket)
        return Socket(socketFileDescriptor: clientSocket)
    }
}
