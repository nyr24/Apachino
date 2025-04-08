const std = @import("std");
const stdout = std.io.getStdOut().writer();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const io = @import("io.zig");
const server_mod = @import("server_conf.zig");
const Server = server_mod.Server;

pub fn main() !void {
    const config_file_contents = try io.read_file(allocator, server_mod.PATH_TO_CONFIG);
    const server = try Server.init(config_file_contents[0..]);
    try server.listen();

    defer allocator.free(config_file_contents);
}
