const std = @import("std");
const stdout = std.io.getStdOut().writer();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const SocketConf = @import("server_conf.zig");
const Request = @import("request.zig");
const RequestError = Request.RequestError;

const io = @import("io.zig");
const json = @import("json.zig");

pub fn main() !void {
    const file_contents = try io.read_file(allocator, "apachino-conf.json");
    defer allocator.free(file_contents);

    _ = try json.parse_config(file_contents[0..]);

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
