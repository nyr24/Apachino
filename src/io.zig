const std = @import("std");

pub fn read_file(allocator: std.mem.Allocator, path_rel: []const u8) ![]u8 {
    const cwd = std.fs.cwd();
    const file_contents = try cwd.readFileAlloc(allocator, path_rel, 10000);
    errdefer allocator.free(file_contents);

    return file_contents;
}
