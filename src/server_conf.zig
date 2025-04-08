const std = @import("std");
const stderr = std.io.getStdErr().writer();
const net = std.net;
const ArrayList = std.ArrayList;
const HashMap = std.StringHashMap;
const RequestMethod = @import("request.zig").Method;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const json = @import("json.zig");
const JsonParsedRepr = json.JsonParsedRepr;
const JsonValueTag = json.JsonValueTag;
const JsonValue = json.JsonValue;

const request = @import("request.zig");
const RequestError = request.RequestError;

pub const PATH_TO_CONFIG = "apachino-conf.json";

pub const Socket = struct {
    address: net.Address,
    stream: net.Stream,

    pub fn init(server_conf: Server) !Socket {
        const addr = net.Address.initIp4(server_conf.ip, server_conf.port);
        const socket = try std.posix.socket(
            addr.any.family,
            std.posix.SOCK.STREAM,
            std.posix.IPPROTO.TCP,
        );
        const stream = net.Stream{ .handle = socket };
        return Socket{ .address = addr, .stream = stream };
    }
};

pub const Route = struct {
    const MULT_ROUTES_JSON_EXAMPLE: []const u8 = "[{ \"url\": ..., methods: [\"GET\", ...], resource_path: \"path_to_index.html\"  }]";
    const SINGLE_ROUTE_JSON_EXAMPLE: []const u8 = "{ \"url\": ..., methods: [\"GET\", ...], resource_path: \"path_to_index.html\"  }";

    url: []const u8 = undefined,
    method: RequestMethod = undefined,
    resource_path: ?[]const u8 = null,

    pub fn init() Route {
        return Route{};
    }
};

pub const Server = struct {
    const DEFAULT_IP = [4]u8{ 127, 0, 0, 1 };
    const DEFAULT_PORT = 8080;

    port: u16 = Server.DEFAULT_PORT,
    ip: [4]u8 = Server.DEFAULT_IP,
    socket: Socket = undefined,
    routes: ArrayList(Route),

    pub fn init(config_file_contents: []const u8) !Server {
        const parsed_json = try json.parse_config(config_file_contents);
        var server_conf = Server{ .routes = try ArrayList(Route).initCapacity(allocator, 5) };

        server_conf.ip = parse_ip(parsed_json);
        server_conf.port = parse_port(parsed_json);
        server_conf.socket = try Socket.init(server_conf);

        return server_conf;
    }

    pub fn listen(self: Server) !void {
        var server = try self.socket.address.listen(.{});
        const connection = try server.accept();
        _ = request.read_request(connection) catch |err| {
            switch (err) {
                RequestError.MethodNotSupported => {
                    try stderr.print("Request Method is not supported by server", .{});
                    std.process.exit(1);
                },
                else => {
                    try stderr.print("Unexpected error occurs, finishing process", .{});
                    std.process.exit(1);
                },
            }
        };
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
                        stderr.print("Configuration error: can't parse Integer value from field 'ip', overflow occurs, value is: {s}", .{ip_str}) catch unreachable;
                        std.process.exit(1);
                    },
                    error.InvalidCharacter => {
                        stderr.print("Configuration error: can't parse Integer value from field 'ip', value is: {s}", .{ip_str}) catch unreachable;
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

    fn parse_routes(self: *Server, parsed_json: JsonParsedRepr) void {
        const routes_arr = unwrap_json_val_arr(parsed_json.get("routes"), null, "routes", Route.MULT_ROUTES_JSON_EXAMPLE);
        for (routes_arr) |route_as_json| {
            self.routes.append(parse_route(route_as_json));
        }
    }

    fn parse_route(route_json_repr: JsonValue) Route {
        var route = Route.init();
        const route_as_table = unwrap_json_val_table(route_json_repr, null, "route", Route.SINGLE_ROUTE_JSON_EXAMPLE);
        const route_url = unwrap_json_val_string(route_as_table.get("url"), null, "url", "/path_to_index.html");
        const route_resource_path = unwrap_json_val_string(route_as_table.get("resource_path"), .{ .Null = 0 }, "resource_path", "/path_to_index.html");

        // TODO: route methods

        route.url = route_url;
        switch (route_resource_path) {
            .String => |resource_path_str| {
                route.resource_path = resource_path_str;
            },
            else => {},
        }

        return route;
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
        json_val = unwrap_json_val(json_val_nullable, field_name);
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
        json_val = unwrap_json_val(json_val_nullable, field_name);
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
        stderr.print("Configuration error: field '{s}' was expected to be of type {any}, found: {s} type\nExample of proper usage: {s}\n", .{
            field, expected_type, found_type, proper_usage_example,
        }) catch unreachable;
        std.process.exit(1);
    }

    fn config_empty_field_err(field: []const u8) void {
        stderr.print("Configuration error: Obligatory field is empty - '{s}'\n", .{field}) catch unreachable;
        std.process.exit(1);
    }

    pub fn deinit(self: Server) void {
        self.routes.deinit();
    }
};
