const std = @import("std");
const env = @import("env.zig");
const Writer = std.fs.File.Writer;

pub fn read_file(allocator: std.mem.Allocator, path_rel: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    const file_contents = try cwd.readFileAlloc(allocator, path_rel, 10_000);
    errdefer allocator.free(file_contents);

    return file_contents;
}

pub fn error_log(comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.BufferedWriter(100, @TypeOf(stderr)){
        .unbuffered_writer = stderr,
    };
    bw.writer().print(format, args) catch {};
    bw.flush() catch {};
}

pub fn log(comptime format: []const u8, args: anytype) void {
    const stderr = std.io.getStdOut().writer();
    var bw = std.io.BufferedWriter(100, @TypeOf(stderr)){
        .unbuffered_writer = stderr,
    };
    bw.writer().print(format, args) catch {};
    bw.flush() catch {};
}
