const std = @import("std");
const stdout = std.io.getStdOut().writer();

const io = @import("io.zig");
const env = @import("env.zig");
const allocator = env.allocator;
const Server = @import("server_conf.zig").Server;

pub fn main() !void {
    const config_file_contents = try io.read_file(allocator, env.PATH_TO_CONFIG);
    defer allocator.free(config_file_contents);
    var server = try Server.init(config_file_contents[0..]);
    defer server.deinit();

    while (true) {
        try server.listen();
    }
}
