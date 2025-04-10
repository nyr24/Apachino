const std = @import("std");
const net = std.net;
const posix = std.posix;
const socket_t = posix.socket_t;
const windows = std.os.windows;
const native_os = @import("env.zig").native_os;
const Server = @import("server_conf.zig").Server;

pub const Socket = struct {
    pub const ReadError = posix.ReadError;
    pub const WriteError = posix.WriteError;

    pub fn accept(listener: Listener) ?socket_t {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);

        const socket_acceptor = posix.accept(listener.socket, &client_address.any, &client_address_len, 0) catch |err| {
            std.debug.print("Error when accepting connection: {}\n", .{err});
            return null;
        };

        return socket_acceptor;
    }

    pub fn close(socket: socket_t) void {
        switch (native_os) {
            .windows => windows.closesocket(socket) catch unreachable,
            else => posix.close(socket),
        }
    }

    pub fn read(socket: socket_t, buffer: []u8) ReadError!usize {
        if (native_os == .windows) {
            return windows.ReadFile(socket, buffer, null);
        }

        return posix.read(socket, buffer);
    }

    pub fn write(socket: socket_t, buffer: []const u8) WriteError!usize {
        if (native_os == .windows) {
            return windows.WriteFile(socket, buffer, null);
        }

        return posix.write(socket, buffer);
    }
};

pub const Listener = struct {
    address: net.Address,
    socket: socket_t,

    pub fn init(server_conf: Server) !Listener {
        const addr = net.Address.initIp4(server_conf.ip, server_conf.port);
        const socket = try posix.socket(
            addr.any.family,
            posix.SOCK.STREAM,
            posix.IPPROTO.TCP,
        );

        return Listener{ .address = addr, .socket = socket };
    }

    pub fn listen(self: Listener) !void {
        try posix.setsockopt(self.socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
        try posix.listen(self.socket, 128);
    }

    pub fn close(self: Listener) void {
        Socket.close(self.socket);
    }
};
