const std = @import("std");
const StaticStringMap = std.static_string_map.StaticStringMap;
const Map = std.AutoHashMap;
const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const Connection = std.net.Server.Connection;
const allocator = @import("env.zig").allocator;

pub const RequestError = error{MethodNotSupported} || anyerror;

pub const Method = enum {
    GET,
    POST,
    OPTIONS,
    PATCH,
    OTHER,

    fn is_supported(self: Method) bool {
        switch (self) {
            .GET => return true,
            .POST => return true,
            .OPTIONS => return false,
            .PATCH => return false,
            .OTHER => return false,
        }
    }
};

pub const MethodMap = StaticStringMap(Method).initComptime(.{
    .{ "GET", Method.GET },
    .{ "POST", Method.POST },
});

pub const Request = struct {
    method: Method = Method.GET,
    url: []const u8 = undefined,
    http_version: [2]u8 = [2]u8{ 1, 1 },

    pub fn init_from_raw_bytes(buffer: []const u8) RequestError!Request {
        var request = Request{};

        var parser = try RequestParser.init(buffer);
        defer parser.deinit();

        parser.parse_request(&request);
        if (!request.method.is_supported()) {
            return RequestError.MethodNotSupported;
        }

        return request;
    }
};

const TokenFn: type = fn (token: []const u8, req: *Request) void;
const TokenFnMap = Map(u8, *const TokenFn);

pub const RequestParser = struct {
    curr_line_n: usize = 0,
    curr_ind: usize = 0,
    curr_token_n: u8 = 0,
    buffer: []const u8,
    // for each line of request contents
    // we create a list of functions
    // which we want to call on tokens with certain indices,
    // which are keys of maps
    tokenFnTable: [1]TokenFnMap,

    pub fn init(buffer: []const u8) !RequestParser {
        var tokenFnTable: [1]TokenFnMap = undefined;

        for (0..tokenFnTable.len) |i| {
            var map = std.AutoHashMap(u8, *const TokenFn).init(allocator);
            try fill_map_for_line_n(i, &map);
            tokenFnTable[i] = map;
        }

        return RequestParser{
            .buffer = buffer,
            .tokenFnTable = tokenFnTable,
        };
    }

    pub fn deinit(self: *RequestParser) void {
        for (0..self.tokenFnTable.len) |i| {
            self.tokenFnTable[i].deinit();
        }
    }

    pub fn parse_request(self: *RequestParser, req: *Request) void {
        _ = self.skip_ws();

        for (0..self.tokenFnTable.len) |i| {
            _ = i;
            if (self.curr_ind < self.buffer.len) {
                if (self.tokenFnTable[self.curr_line_n].count() == 0) {
                    const end_reached = self.skip_curr_line();
                    if (end_reached) {
                        break;
                    }
                }
                self.parse_line_and_operate_on_tokens(req);
                self.curr_line_n += 1;
            }
        }
    }

    fn parse_line_and_operate_on_tokens(self: *RequestParser, req: *Request) void {
        var curr_token: []const u8 = undefined;
        var start_ind: usize = undefined;
        var tokenFnUsed: usize = 0;

        while (self.curr_ind < self.buffer.len and self.get_curr_ch() != '\n') : (self.advance()) {
            while (self.curr_ind < self.buffer.len and self.get_curr_ch() != '\n' and std.ascii.isWhitespace(self.buffer[self.curr_ind])) : (self.advance()) {}
            if (self.get_curr_ch() == '\n') {
                return;
            }

            start_ind = self.curr_ind;
            while (self.curr_ind < self.buffer.len and !std.ascii.isWhitespace(self.get_curr_ch())) : (self.advance()) {}

            const tokenFn = self.tokenFnTable[self.curr_line_n].get(self.curr_token_n);

            if (tokenFn) |tokenFn_| {
                curr_token = self.buffer[start_ind..self.curr_ind];
                self.curr_token_n += 1;
                tokenFn_(curr_token, req);
                tokenFnUsed += 1;

                // no more tokens to operate on
                if (tokenFnUsed >= self.tokenFnTable[self.curr_line_n].count()) {
                    self.curr_token_n = 0;
                    return;
                }
            }
        }
    }

    fn fill_map_for_line_n(line_n: usize, map: *TokenFnMap) !void {
        switch (line_n) {
            0 => {
                try map.*.put(0, &get_method_from_token);
                try map.*.put(1, &get_url_from_token);
            },
            else => unreachable,
        }
    }

    inline fn get_curr_ch(self: RequestParser) u8 {
        return self.buffer[self.curr_ind];
    }

    inline fn advance(self: *RequestParser) void {
        self.curr_ind += 1;
    }

    // returns true if buffer end reached
    inline fn skip_ws(self: *RequestParser) bool {
        while (self.curr_ind < self.buffer.len and std.ascii.isWhitespace(self.get_curr_ch())) : (self.advance()) {
            if (self.get_curr_ch() == '\n') {
                self.curr_line_n += 1;
            }
        }

        return self.curr_ind >= self.buffer.len;
    }

    // returns true if buffer end reached
    inline fn skip_curr_line(self: *RequestParser) bool {
        while (self.curr_ind < self.buffer.len and self.get_curr_ch() != '\n') : (self.advance()) {}
        self.advance();

        return self.curr_ind >= self.buffer.len;
    }
};

fn get_method_from_token(token: []const u8, req: *Request) void {
    const method: ?Method = MethodMap.get(token);
    if (method) |method_non_null| {
        req.method = method_non_null;
    }
}

fn get_url_from_token(token: []const u8, req: *Request) void {
    if (token.len == 0) {
        return;
    }
    req.url = token;
}
