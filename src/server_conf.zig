const ArrayList = @import("std").ArrayList;
const RequestMethod = @import("request.zig").Method;
var gpa = @import("std").heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const RouteConf = struct {
    url: []const u8 = undefined,
    method: RequestMethod = undefined,
    resource_path: ?[]const u8 = null,

    pub fn init() RouteConf {
        return RouteConf{};
    }
};

pub const ServerConf = struct {
    routes: ArrayList(RouteConf),

    pub fn init() !ServerConf {
        return ServerConf{ .routes = try ArrayList(RouteConf).initCapacity(allocator, 5) };
    }

    pub fn deinit(self: ServerConf) void {
        self.routes.deinit();
    }
};
