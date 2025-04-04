const std = @import("std");
const stdout = std.io.getStdOut().writer();
const SocketConf = @import("config.zig");
const Request = @import("request.zig");

pub fn main() !void {
    const socket = try SocketConf.Socket.init();
    var server = try socket._address.listen(.{});

    const connection = try server.accept();
    const req = try Request.read_request(connection);

    std.debug.print("Req method: {any}\nReq url: {s}\n", .{ req.method, req.url });
}
