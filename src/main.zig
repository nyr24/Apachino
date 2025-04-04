const std = @import("std");
const stdout = std.io.getStdOut().writer();
const SocketConf = @import("config.zig");
const Request = @import("request.zig");
const RequestError = Request.RequestError;

pub fn main() !void {
    const socket = try SocketConf.Socket.init();
    var server = try socket._address.listen(.{});

    const connection = try server.accept();
    const req = Request.read_request(connection) catch |err| {
        switch (err) {
            RequestError.MethodNotSupported => {
                try stdout.print("Request Method is not supported by server", .{});
                std.process.exit(1);
            },
            else => {
                try stdout.print("Unexpected error occurs, finishing process", .{});
                std.process.exit(1);
            },
        }
    };

    std.debug.print("Req method: {any}\nReq url: {s}\n", .{ req.method, req.url });
}
