const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const fmt = std.fmt;
const request = @import("request.zig");
const Request = request.Request;
const config = @import("server_conf.zig");
const Server = config.Server;
const io = @import("io.zig");
const OpenError = std.fs.Dir.OpenError;
const gpa = @import("env.zig").allocator;

const StatusType = enum {
    Ok,
    NotFound,

    fn get_status(self: StatusType) Status {
        switch (self) {
            .Ok => return Status.init(200, "OK"),
            .NotFound => return Status.init(404, "Not-Found"),
        }
    }
};

const Status = struct {
    code: u16,
    message: []const u8,

    fn init(code: u16, message: []const u8) Status {
        return Status{
            .code = code,
            .message = message,
        };
    }
};

const HeaderType = enum {
    ContentLength,
    ContentType,
    Connection,

    fn get_header_key(self: HeaderType) []const u8 {
        switch (self) {
            .ContentLength => return "Content-Length",
            .ContentType => return "Content-Type",
            .Connection => return "Connection",
        }
    }
};

const Header = struct {
    key: []const u8,
    value: []const u8,

    fn init(header_type: HeaderType, value: []const u8) Header {
        return Header{
            .key = HeaderType.get_header_key(header_type),
            .value = value,
        };
    }
};

// TODO:
// mime-types
pub const Response = struct {
    status: Status = undefined,
    headers: ArrayList(u8) = undefined,
    body: ?[]u8 = null,

    pub fn init(req: Request, server_conf: Server) !Response {
        var response = Response{};

        response.set_body(req, server_conf);
        try response.set_headers(gpa);

        return response;
    }

    pub fn deinit(self: Response) void {
        self.headers.deinit();
        if (self.body) |body_non_null| {
            gpa.free(body_non_null);
        }
    }

    fn set_headers(self: *Response, alloc: std.mem.Allocator) !void {
        self.headers = try ArrayList(u8).initCapacity(alloc, 500);
        var contentLength: usize = 0;
        if (self.body) |body_non_null| {
            contentLength = body_non_null.len;
        }
        _ = try fmt.bufPrint(self.headers.items, "HTTP/1.1 {d} {s}" ++ "\nContent-Length: {d}" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n", .{ self.status.code, self.status.message, contentLength });
    }

    fn set_body(self: *Response, req: Request, server_conf: Server) void {
        if (server_conf.routes.get(req.url)) |route| {
            if (route.resource_path) |path_non_null| {
                self.status = StatusType.get_status(.Ok);
                self.body = io.read_file(gpa, path_non_null) catch |err| {
                    switch (err) {
                        OpenError.FileNotFound => {
                            std.debug.print("Can't read file: was not found at: {s}\n", .{path_non_null});
                            self.status = StatusType.get_status(.NotFound);
                            return;
                        },
                        OpenError.AccessDenied => {
                            std.debug.print("Can't read file: permission denied at: {s}\n", .{path_non_null});
                            self.status = StatusType.get_status(.NotFound);
                            return;
                        },
                        else => {
                            std.debug.print("Can't read file: unexpected error occurred at: {s}\n", .{path_non_null});
                            self.status = StatusType.get_status(.NotFound);
                            return;
                        },
                    }
                };
            } else {
                self.status = StatusType.get_status(.NotFound);
            }
        }
    }
};
