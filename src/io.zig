const std = @import("std");
const env = @import("env.zig");
const Writer = std.fs.File.Writer;
const stdout = std.io.getStdOut().writer();

pub fn read_file(allocator: std.mem.Allocator, path_rel: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    const file_contents = try cwd.readFileAlloc(allocator, path_rel, 10_000);
    errdefer allocator.free(file_contents);

    return file_contents;
}

pub fn error_log(comptime format: []const u8, args: anytype) void {
    stdout.print(format, args) catch {};
}
