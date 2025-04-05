const std = @import("std");
const ArrayList = std.ArrayList;
const stderr = std.io.getStdErr().writer();

const ServerConfMod = @import("server_conf.zig");
const ServerConf = ServerConfMod.ServerConf;
const RouteConf = ServerConfMod.RouteConf;
const RequestMethod = @import("request.zig").Method;

// entry point for json parsing
pub fn parse_config(contents: []u8) ServerConf {
    const conf_parser = ConfigParser.init(contents);
    return conf_parser.parse();
}

const ParseConfigErr = error{
    RouteNotFullyDefined,
    ConfigEndReachedEarly,
};

const Expectable = struct {
    contents: []const u8,
    is_optional: bool = false,

    fn init(contents: []const u8, is_opt: bool) Expectable {
        return Expectable{
            .contents = contents,
            .is_optional = is_opt,
        };
    }
};

const ConfigParser = struct {
    buffer: []u8,
    curr_ind: usize = 0,
    curr_line_n: usize = 0,
    end_reached: bool = false,
    route_expectables: comptime[3]Expectable = [3]Expectable{
        Expectable.init("url", true),
        Expectable.init("method", true),
        Expectable.init("resource_path", true),
    },

    pub fn init(buffer: []u8) ConfigParser {
        return ConfigParser{ .buffer = buffer };
    }

    pub fn parse(self: ConfigParser) ParseConfigErr!ServerConf {
        var server_conf = ServerConf.init();

        self.expect_and_advance(Expectable.init("{"), true);
        self.expect_and_advance(Expectable.init("routes"), true);
        self.expect_and_advance(Expectable.init(":"), true);
        self.expect_and_advance(Expectable.init("["), true);

        self.parse_routes_arr();

        self.expect_and_advance(Expectable.init("]"), true);
        self.expect_and_advance(Expectable.init("}"), true);

        if (self.end_reached) {
            return server_conf;
        } else {
            return error.ConfigEndReachedEarly;
        }
    }

    fn parse_routes_arr() {
        // TODO:
    }

    fn parse_route(self: ConfigParser) ParseConfigErr!RouteConf {
        var route = RouteConf.init();

        self.expect_and_advance(Expectable.init("{"), true);
        self.expect_and_advance(Expectable.init("}"), true);

        if (self.validate_parsed_route(route)) {
            return route;
        } else {
            return error.RouteNotFullyDefined;
        }
    }

    fn validate_parsed_route(self: ConfigParser, route: RouteConf) bool {
        return route.method != undefined and route.url != undefined;
    }

    fn expect_one_of(self: *ConfigParser, expectables: []const Expectable) {
        for (expectables) |expectable| {
            self.expect_and_advance(expectable, true);
        }
    }

    fn expect_and_advance(self: *ConfigParser, expectable: Expectable, skip_ws_before: bool) void {
        if (skip_ws_before) {
            self.skip_ws();
        }

        const start_ind = self.curr_ind;
        var expected_ind: usize = 0;

        while (self.curr_ind < self.buffer.len and expected_ind < expectable.contents.len and self.buffer[self.curr_ind] == expectable.contents[expected_ind]) {
            self.curr_ind += 1;
            expected_ind += 1;
        }

        if (expected_ind == expectable.contents.len) {
            // success
            return;
        } else {
            if (self.curr_ind >= self.buffer.len) {
                self.end_reached = true;
                stderr.print("End of config is reached early, line {d}, expected {s}", .{ self.curr_line_n, expected }) catch unreachable;
                std.process.exit(1);
            } else {
                self.curr_ind = start_ind;
                if (!expectable.is_optional) {
                    stderr.print("Unexpected token at line {d}, expected: {s}", .{ self.curr_line_n, expected }) catch unreachable;
                    std.process.exit(1);
                }
            }
        }
    }

    // returns true if buffer end reached
    inline fn skip_ws(self: *ConfigParser) void {
        while (self.curr_ind < self.buffer.len and std.ascii.isWhitespace(self.buffer[self.curr_ind])) : (self.curr_ind += 1) {
            if (self.buffer[self.curr_ind] == '\n') {
                self.curr_line_n += 1;
            }
        }

        if (self.curr_ind >= self.buffer.len) {
            self.end_reached = true;
        }
    }
};
