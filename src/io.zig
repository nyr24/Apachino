const std = @import("std");

pub fn read_file(path_rel: []const u8, buffer: []u8) !void {
    const cwd = std.fs.cwd();
    _ = try cwd.readFile(path_rel, buffer);
}
