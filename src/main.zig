const std = @import("std");
const stdout = std.io.getStdOut().writer();
const allocator = @import("env.zig").allocator;

const io = @import("io.zig");
const server_mod = @import("server_conf.zig");
const Server = server_mod.Server;

pub fn main() !void {
    const config_file_contents = try io.read_file(allocator, server_mod.PATH_TO_CONFIG);
    defer allocator.free(config_file_contents);
    var server = try Server.init(config_file_contents[0..]);
    defer server.deinit();

    while (true) {
        try server.listen();
    }
}
