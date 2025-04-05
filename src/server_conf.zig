const std = @import("std");
const ArrayList = std.ArrayList;
const RequestMethod = @import("request.zig").Method;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const net = @import("std").net;

// TODO: get this from config;
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
            std.posix.IPPROTO.TCP,
        );
        const stream = net.Stream{ .handle = socket };
        return Socket{ ._address = addr, ._stream = stream };
    }
};

pub const RouteConf = struct {
    url: []const u8 = undefined,
    method: RequestMethod = undefined,
    resource_path: ?[]const u8 = null,

    pub fn init() RouteConf {
        return RouteConf{};
    }
};

pub const ServerConf = struct {
    ip: [4]u8 = [4]u8{ 127, 0, 0, 1 },
    port: u16 = 8080,
    routes: ArrayList(RouteConf),

    pub fn init() !ServerConf {
        return ServerConf{ .routes = try ArrayList(RouteConf).initCapacity(allocator, 5) };
    }

    pub fn deinit(self: ServerConf) void {
        self.routes.deinit();
    }
};
