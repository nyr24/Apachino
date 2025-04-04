const std = @import("std");
const ArrayList = std.ArrayList;
const stderr = std.io.getStdErr().writer();
const ServerConfMod = @import("server_conf.zig");
const ServerConf = ServerConfMod.ServerConf;
const RouteConf = ServerConfMod.RouteConf;
const RequestMethod = @import("request.zig").Method;

// entry point for json parsing
pub fn parse_json(contents: []u8) ServerConf {
    const json_parser = JsonParser.init(contents);
    return json_parser.parse();
}

const ParseConfigErr = error{
    RouteNotFullyDefined,
};

const JsonParser = struct {
    buffer: []u8,
    curr_ind: usize = 0,
    curr_line_n: usize = 0,
    end_reached: bool = false,

    pub fn init(buffer: []u8) JsonParser {
        return JsonParser{ .buffer = buffer };
    }

    pub fn parse(self: JsonParser) ServerConf {
        var server_conf = ServerConf.init();

        _ = self.skip_ws();
        self.expect_and_advance("{");
        _ = self.skip_ws();
        self.expect_and_advance("routes");
        _ = self.skip_ws();
        self.expect_and_advance(":");
        _ = self.skip_ws();

        return server_conf;
    }

    fn parse_routes_arr() ArrayList(RouteConf) {
        // TODO:
    }

    fn parse_route() ParseConfigErr!RouteConf {
        var route = RouteConf.init();

        // TODO:

        if (is_valid_route(route)) {
            return route;
        } else {
            return error.RouteNotFullyDefined;
        }
    }

    fn is_valid_route(route: RouteConf) bool {
        return route.method != undefined and route.url != undefined;
    }

    fn expect_and_advance(self: *JsonParser, expected: []const u8) void {
        const start_ind = self.curr_ind;
        var expected_ind: usize = 0;

        while (self.curr_ind < self.buffer.len and expected_ind < expected.len and self.buffer[self.curr_ind] == expected[expected_ind]) {
            self.curr_ind += 1;
            expected_ind += 1;
        }

        if (expected_ind == expected.len) {
            // success
            return;
        } else {
            if (self.curr_ind >= self.buffer.len) {
                self.end_reached = true;
                stderr.print("End of config is reached early, line {d}, expected {s}", .{ self.curr_line_n, expected }) catch unreachable;
                std.process.exit(1);
            } else {
                self.curr_ind = start_ind;
                stderr.print("Unexpected token at line {d}, expected: {s}", .{ self.curr_line_n, expected }) catch unreachable;
                std.process.exit(1);
            }
        }
    }

    // returns true if buffer end reached
    inline fn skip_ws(self: *JsonParser) bool {
        while (self.curr_ind < self.buffer.len and std.ascii.isWhitespace(self.buffer[self.curr_ind])) : (self.curr_ind += 1) {
            if (self.buffer[self.curr_ind] == '\n') {
                self.curr_line_n += 1;
            }
        }

        if (self.curr_ind >= self.buffer.len) {
            self.end_reached = true;
        }
        return self.end_reached;
    }
};
