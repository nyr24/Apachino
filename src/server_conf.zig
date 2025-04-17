const std = @import("std");
const env = @import("env.zig");
const posix = std.posix;
const ArrayList = std.ArrayList;
const HashMap = std.StringHashMap;
const allocator = env.allocator;

const io = @import("io.zig");
const json = @import("json.zig");
const JsonParsedRepr = json.JsonParsedRepr;
const JsonValueTag = json.JsonValueTag;
const JsonValue = json.JsonValue;
const request = @import("request.zig");
const Request = request.Request;
const RequestError = request.RequestError;
const RequestMethod = request.Method;
const RequestMethodMap = request.MethodMap;
const response = @import("response.zig");
const Response = response.Response;
const socket = @import("socket.zig");
const Listener = socket.Listener;
const Socket = socket.Socket;

const JsonExample = struct {
    const MULT_ROUTES_JSON_EXAMPLE: []const u8 = "[{ \"url\": ..., methods: [\"GET\", ...], resource_path: \"path_to_index.html\"  }]";
    const SINGLE_ROUTE_JSON_EXAMPLE: []const u8 = "{ \"url\": ..., methods: [\"GET\", ...], resource_path: \"path_to_index.html\"  }";
    const URL_JSON_EXAMPLE: []const u8 = "/page1";
    const RESOURCE_PATH_JSON_EXAMPLE: []const u8 = "/path_to_index.html";
    const METHODS_EXAMPLE: []const u8 = "[\"GET\", ...]";
    const RESOURCE_BASE_PATH: []const u8 = "\"resource_base_path\": \"./res\"";
};

pub const Route = struct {
    url: []const u8 = undefined,
    methods: HashMap(RequestMethod),
    resource_path: ?[]const u8 = null,

    pub fn init() !Route {
        return Route{ .methods = HashMap(RequestMethod).init(allocator) };
    }

    pub fn deinit(self: *Route) void {
        self.methods.deinit();
    }
};

pub const Server = struct {
    const DEFAULT_IP = [4]u8{ 127, 0, 0, 1 };
    const DEFAULT_PORT = 8080;

    port: u16 = Server.DEFAULT_PORT,
    ip: [4]u8 = Server.DEFAULT_IP,
    socket_listener: Listener = undefined,
    res_base_path: ?[]const u8 = null,
    routes: HashMap(Route),

    pub fn init(config_file_contents: []const u8) !Server {
        const parsed_json = try json.parse_config(config_file_contents);
        var server_conf = Server{ .routes = HashMap(Route).init(allocator) };

        server_conf.ip = parse_ip(parsed_json);
        server_conf.port = parse_port(parsed_json);
        server_conf.socket_listener = try Listener.init(server_conf);
        server_conf.res_base_path = parse_base_path(parsed_json);
        try server_conf.parse_routes(parsed_json);

        return server_conf;
    }

    pub fn deinit(self: *Server) void {
        var routes_iter = self.routes.valueIterator();
        while (routes_iter.next()) |route| {
            route.*.deinit();
        }
        self.routes.deinit();
    }

    pub fn listen(self: Server) !void {
        try self.socket_listener.listen();
        defer self.socket_listener.close();

        while (true) {
            if (Socket.accept(self.socket_listener)) |socket_acceptor| {
                Socket.set_read_timeout(socket_acceptor) catch |err| {
                    io.error_log("Can't set socketopt RCVTIMEO, {any}\n", .{err});
                };
                Socket.set_write_timeout(socket_acceptor) catch |err| {
                    io.error_log("Can't set socketopt SNDTIMEO, {any}\n", .{err});
                };
                defer Socket.close(socket_acceptor);

                var request_contents: [1000]u8 = undefined;
                _ = Socket.read_all(socket_acceptor, request_contents[0..]) catch |err| {
                    io.error_log("Socket read error: {any}\n", .{err});
                    continue;
                };

                const req = Request.init_from_raw_bytes(request_contents[0..]) catch |err| {
                    switch (err) {
                        RequestError.MethodNotSupported => {
                            io.error_log("Warning: Request Method is not supported by server", .{});
                            std.process.exit(1);
                        },
                        else => {
                            io.error_log("Unexpected error occurs, finishing process", .{});
                            std.process.exit(1);
                        },
                    }
                };
                defer req.deinit();

                const resp = try Response.init(req, self);
                defer resp.deinit();

                _ = Socket.write_all(socket_acceptor, resp.headers) catch |err| {
                    io.error_log("Socket write error: {any}\n", .{err});
                    continue;
                };
                if (resp.body) |resp_body| {
                    _ = Socket.write_all(socket_acceptor, resp_body) catch |err| {
                        io.error_log("Socket write error: {any}\n", .{err});
                        continue;
                    };
                }
            } else {
                continue;
            }
        }
    }

    fn parse_ip(parsed_json: JsonParsedRepr) [4]u8 {
        var result_ip: [4]u8 = undefined;
        const ip_str = unwrap_json_val_string(parsed_json.get("ip"), .{ .String = Server.DEFAULT_IP[0..] }, "ip", "127.0.0.1");
        var ip_parts_iter = std.mem.splitSequence(u8, ip_str, ".");
        var i: usize = 0;

        while (ip_parts_iter.next()) |ip_part| {
            if (i >= result_ip.len) {
                break;
            }
            if (std.fmt.parseInt(u8, ip_part, 10)) |ip_as_u8| {
                result_ip[i] = ip_as_u8;
                i += 1;
            } else |err| {
                switch (err) {
                    error.Overflow => {
                        io.error_log("Configuration error: can't parse Integer value from field 'ip', overflow occurs, value is: {s}", .{ip_str});
                        std.process.exit(1);
                    },
                    error.InvalidCharacter => {
                        io.error_log("Configuration error: can't parse Integer value from field 'ip', value is: {s}", .{ip_str});
                        std.process.exit(1);
                    },
                    else => unreachable,
                }
                return Server.DEFAULT_IP;
            }
        }
        return result_ip;
    }

    fn parse_port(parsed_json: JsonParsedRepr) u16 {
        const port_as_i32 = unwrap_json_val_number(parsed_json.get("port"), .{ .Number = Server.DEFAULT_PORT }, "port", "8080");
        const port_as_u16: u16 = @intCast(port_as_i32);
        return port_as_u16;
    }

    fn parse_routes(self: *Server, parsed_json: JsonParsedRepr) !void {
        const routes_arr = unwrap_json_val_arr(parsed_json.get("routes"), null, "routes", JsonExample.MULT_ROUTES_JSON_EXAMPLE);
        for (routes_arr.items) |route_as_json| {
            try self.add_route(route_as_json);
        }
    }

    fn parse_base_path(parsed_json: JsonParsedRepr) ?[]const u8 {
        const res_base_path = parsed_json.get("resource_base_path");
        if (res_base_path) |res_base_non_null| {
            switch (res_base_non_null) {
                .String => |res_base_unwrapped| {
                    return res_base_unwrapped;
                },
                else => {
                    config_type_err("resource_base_path", .String, @tagName(res_base_non_null), JsonExample.RESOURCE_BASE_PATH);
                    return null;
                },
            }
        }
        return null;
    }

    fn add_route(self: *Server, route_json_repr: JsonValue) !void {
        var route = try Route.init();
        const route_as_table = unwrap_json_val_table(route_json_repr, null, "route", JsonExample.SINGLE_ROUTE_JSON_EXAMPLE);
        const route_url = unwrap_json_val_string(route_as_table.get("url"), null, "url", JsonExample.URL_JSON_EXAMPLE);
        const route_methods = unwrap_json_val_arr(route_as_table.get("methods"), null, "methods", JsonExample.METHODS_EXAMPLE);
        const route_resource_path_nullable = route_as_table.get("resource_path");

        route.url = route_url;
        if (route_resource_path_nullable) |route_resource_path| {
            switch (route_resource_path) {
                .String => |resource_path_str| {
                    route.resource_path = resource_path_str;
                },
                else => route.resource_path = null,
            }
        } else {
            route.resource_path = null;
        }

        for (route_methods.items) |method_json| {
            const route_method_nullable = parse_route_method(method_json);
            if (route_method_nullable) |route_method| {
                try route.methods.put(route_method, RequestMethodMap.get(route_method).?);
            }
        }

        try self.routes.put(route_url, route);
    }

    fn parse_route_method(method_json: JsonValue) ?[]const u8 {
        const method_str = unwrap_json_val_string(method_json, null, "item of methods []", JsonExample.METHODS_EXAMPLE);
        if (RequestMethodMap.has(method_str)) {
            return method_str;
        } else {
            io.error_log("Configuration warning: Unknown request method: {s}", .{method_str});
            return null;
        }
    }

    fn unwrap_json_val(json_val_nullable: ?JsonValue, field_name: []const u8) JsonValue {
        if (json_val_nullable) |json_val| {
            return json_val;
        } else {
            config_empty_field_err(field_name);
            unreachable;
        }
    }

    fn unwrap_json_val_or_default(json_val_nullable: ?JsonValue, default_val: JsonValue) JsonValue {
        if (json_val_nullable) |json_val| {
            return json_val;
        } else {
            return default_val;
        }
    }

    fn unwrap_json_val_string(json_val_nullable: ?JsonValue, default_val: ?JsonValue, field_name: []const u8, proper_usage_example: []const u8) []const u8 {
        var json_val: JsonValue = undefined;
        if (default_val) |defaul_val_non_null| {
            json_val = unwrap_json_val_or_default(json_val_nullable, defaul_val_non_null);
        } else {
            json_val = unwrap_json_val(json_val_nullable, field_name);
        }
        switch (json_val) {
            .String => |json_val_str| {
                return json_val_str;
            },
            else => {
                config_type_err(field_name, .String, @tagName(json_val), proper_usage_example);
                unreachable;
            },
        }
    }

    fn unwrap_json_val_number(json_val_nullable: ?JsonValue, default_val: ?JsonValue, field_name: []const u8, proper_usage_example: []const u8) i32 {
        var json_val: JsonValue = undefined;
        if (default_val) |default_val_non_null| {
            json_val = unwrap_json_val_or_default(json_val_nullable, default_val_non_null);
        } else {
            json_val = unwrap_json_val(json_val_nullable, field_name);
        }
        switch (json_val) {
            .Number => |json_val_number| {
                return json_val_number;
            },
            else => {
                config_type_err(field_name, .Number, @tagName(json_val), proper_usage_example);
                unreachable;
            },
        }
    }

    fn unwrap_json_val_arr(json_val_nullable: ?JsonValue, default_val: ?JsonValue, field_name: []const u8, proper_usage_example: []const u8) ArrayList(JsonValue) {
        var json_val: JsonValue = undefined;
        if (default_val) |default_val_non_null| {
            json_val = unwrap_json_val_or_default(json_val_nullable, default_val_non_null);
        } else {
            json_val = unwrap_json_val(json_val_nullable, field_name);
        }
        switch (json_val) {
            .Array => |json_val_arr| {
                return json_val_arr;
            },
            else => {
                config_type_err(field_name, .Array, @tagName(json_val), proper_usage_example);
                unreachable;
            },
        }
    }

    fn unwrap_json_val_table(json_val_nullable: ?JsonValue, default_val: ?JsonValue, field_name: []const u8, proper_usage_example: []const u8) HashMap(JsonValue) {
        var json_val: JsonValue = undefined;
        if (default_val) |default_val_non_null| {
            json_val = unwrap_json_val_or_default(json_val_nullable, default_val_non_null);
        } else {
            json_val = unwrap_json_val(json_val_nullable, field_name);
        }
        switch (json_val) {
            .Table => |json_val_table| {
                return json_val_table;
            },
            else => {
                config_type_err(field_name, .Table, @tagName(json_val), proper_usage_example);
                unreachable;
            },
        }
    }

    fn config_type_err(field: []const u8, expected_type: JsonValueTag, found_type: [:0]const u8, proper_usage_example: []const u8) void {
        io.error_log("Configuration error: field '{s}' was expected to be of type {any}, found: {s} type\nExample of proper usage: {s}\n", .{
            field, expected_type, found_type, proper_usage_example,
        });
        std.process.exit(1);
    }

    fn config_empty_field_err(field: []const u8) void {
        io.error_log("Configuration error: Obligatory field is empty - '{s}'\n", .{field});
        std.process.exit(1);
    }
};
