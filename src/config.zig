const std = @import("std");
const net = @import("std").net;

const localhost = [4]u8{ 127, 0, 0, 1 };
const port: u16 = 8080;

pub const Socket = struct {
    _address: net.Address,
    _stream: net.Stream,

    pub fn init() !Socket {
        const addr = net.Address.initIp4(localhost, port);
        const socket = try std.posix.socket(
            addr.any.family,
            std.posix.SOCK.STREAM,
            // TODO: change to UDP
            std.posix.IPPROTO.TCP,
        );
        const stream = net.Stream{ .handle = socket };
        return Socket{ ._address = addr, ._stream = stream };
    }
};
