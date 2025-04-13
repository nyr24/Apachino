const std = @import("std");
const builtin = @import("builtin");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();
pub const native_os = builtin.os.tag;
pub const PATH_TO_CONFIG = "apachino-conf.json";
