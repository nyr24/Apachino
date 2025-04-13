const std = @import("std");
const io = @import("io.zig");
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
            io.error_log("Error when accepting connection: {}\n", .{err});
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

    pub fn read_all(socket: socket_t, buffer: []u8) ReadError!usize {
        if (native_os == .windows) {
            return windows.ReadFile(socket, buffer, null);
        }

        var bytes_read: usize = 0;
        while (bytes_read < buffer.len) {
            const readed = try posix.read(socket, buffer);
            if (readed == 0) {
                return ReadError.OperationAborted;
            }
            bytes_read += readed;
        }
        return bytes_read;
    }

    pub fn write_all(socket: socket_t, buffer: []const u8) WriteError!usize {
        if (native_os == .windows) {
            return windows.WriteFile(socket, buffer, null);
        }

        var bytes_written: usize = 0;
        while (bytes_written < buffer.len) {
            const curr_written = try posix.write(socket, buffer);
            if (curr_written == 0) {
                return WriteError.OperationAborted;
            }
            bytes_written += curr_written;
        }
        return bytes_written;
    }

    pub fn set_read_timeout(socket: socket_t) !void {
        const timeout = posix.timeval{ .tv_sec = 2, .tv_usec = 500_000 };
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(timeout));
    }

    pub fn set_write_timeout(socket: socket_t) !void {
        const timeout = posix.timeval{ .tv_sec = 2, .tv_usec = 500_000 };
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(timeout));
    }

    pub fn print_address(socket: socket_t) !void {
        var address: std.net.Address = undefined;
        var len: posix.socklen_t = @sizeOf(net.Address);

        try posix.getsockname(socket, &address.any, &len);
        io.error_log("Server is listening on {}\n", .{address});
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
        try Socket.print_address(self.socket);
    }

    pub fn close(self: Listener) void {
        Socket.close(self.socket);
    }
};
