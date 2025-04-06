const std = @import("std");
const stdout = std.io.getStdOut().writer();
const SocketConf = @import("server_conf.zig");
const Request = @import("request.zig");
const RequestError = Request.RequestError;

const io = @import("io.zig");
const json = @import("json.zig");

pub fn main() !void {
    var conf_buffer: [600]u8 = undefined;
    try io.read_file("apachino-conf.json", &conf_buffer);

    std.debug.print("Config: {s}", .{conf_buffer});

    _ = try json.parse_config(conf_buffer[0..]);

    const socket = try SocketConf.Socket.init();
    var server = try socket._address.listen(.{});

    const connection = try server.accept();
    _ = Request.read_request(connection) catch |err| {
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
}
