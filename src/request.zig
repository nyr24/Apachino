const std = @import("std");
const io = @import("io.zig");
const StaticStringMap = std.static_string_map.StaticStringMap;
const Map = std.AutoHashMap;
const StringMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const String = std.ArrayList(u8);
const Connection = std.net.Server.Connection;
const allocator = @import("env.zig").allocator;
const response = @import("response.zig");
const MimeType = response.MimeType;

pub const RequestError = error{MethodNotSupported} || anyerror;

pub const Method = enum {
    GET,
    POST,
    PATCH,
    PUT,
    DELETE,
    OPTIONS,
    OTHER,

    fn is_supported(self: Method) bool {
        switch (self) {
            .GET => return true,
            // queries to BD's are required for them
            .POST => return false,
            .OPTIONS => return false,
            .PATCH => return false,
            .PUT => return false,
            .DELETE => return false,
            .OTHER => return false,
        }
    }
};

pub const MethodMap = StaticStringMap(Method).initComptime(.{
    .{ "GET", Method.GET },
    .{ "POST", Method.POST },
    .{ "PATCH", Method.PATCH },
    .{ "PUT", Method.PUT },
    .{ "DELETE", Method.DELETE },
    .{ "OPTIONS", Method.OPTIONS },
});

pub const Request = struct {
    method: Method = undefined,
    url: []const u8 = undefined,
    mime_types: ArrayList(MimeType),

    pub fn init_from_raw_bytes(buffer: []const u8) RequestError!Request {
        var request = Request{ .mime_types = try ArrayList(MimeType).initCapacity(allocator, 5) };

        var parser = try RequestParser.init(buffer);
        defer parser.deinit();

        parser.parse_request(&request);
        if (!request.method.is_supported()) {
            return RequestError.MethodNotSupported;
        }

        return request;
    }

    pub fn deinit(self: Request) void {
        self.mime_types.deinit();
    }
};

const TokenFn = fn (token: []const u8, req: *Request) void;
const TokenCmpFn = fn (token: []const u8) bool;
const TokenInnerMap = Map(u8, *const TokenFn);
const TokenOuterMap = StringMap(TokenInnerMap);
const RequestMapKey: []const u8 = "Request";

pub const RequestParser = struct {
    curr_line_n: usize = 0,
    curr_ind: usize = 0,
    buffer: []const u8,
    // for each line of request contents
    // we create a list of functions
    // which we want to call on tokens with certain indices,
    token_outer_map: TokenOuterMap,

    pub fn init(buffer: []const u8) !RequestParser {
        const token_outer_map = try RequestParser.init_map();

        return RequestParser{
            .buffer = buffer,
            .token_outer_map = token_outer_map,
        };
    }

    pub fn deinit(self: *RequestParser) void {
        var map_it = self.token_outer_map.valueIterator();

        while (map_it.next()) |map_inner| {
            map_inner.deinit();
        }

        self.token_outer_map.deinit();
    }

    pub fn parse_request(self: *RequestParser, req: *Request) void {
        _ = self.skip_ws();

        // prevent unnecessary iterations
        var map_values_used: usize = 0;
        const map_values_count = self.token_outer_map.count();

        while (!self.is_end_reached() and map_values_used < map_values_count) {
            const is_map_value_used = self.parse_line_and_operate_on_tokens(req);
            if (is_map_value_used) {
                map_values_used += 1;
            }
        }
    }

    fn parse_line_and_operate_on_tokens(self: *RequestParser, req: *Request) bool {
        _ = self.skip_ws_but_not_newline();
        if (self.get_curr_ch() == '\n') {
            self.curr_line_n += 1;
            return false;
        }

        const first_token = self.slice_token(true);
        var curr_token_n: u8 = 0;

        var inner_map: ?TokenInnerMap = undefined;
        if (self.curr_line_n == 0) {
            inner_map = self.token_outer_map.get(RequestMapKey);
        } else {
            inner_map = self.token_outer_map.get(first_token);
        }

        if (inner_map) |inner_map_unwrapped| {
            var inner_map_it = inner_map_unwrapped.iterator();

            outer: while (inner_map_it.next()) |inner_map_entry| {
                const need_token_n = inner_map_entry.key_ptr.*;
                _ = self.skip_ws_but_not_newline();

                while (curr_token_n < need_token_n) {
                    _ = self.skip_ws_but_not_newline();
                    const is_end = self.skip_token();
                    curr_token_n += 1;
                    if (is_end) {
                        continue :outer;
                    }
                }

                const need_token = self.slice_token(false);
                curr_token_n += 1;
                inner_map_entry.value_ptr.*(need_token, req);
            }

            if (self.get_curr_ch() != '\n') {
                _ = self.skip_curr_line();
                self.curr_line_n += 1;
                return true;
            }

            return true;
        } else {
            _ = self.skip_curr_line();
            self.curr_line_n += 1;
            return false;
        }
    }

    fn init_map() !TokenOuterMap {
        var map_for_line_0 = TokenInnerMap.init(allocator);
        errdefer map_for_line_0.deinit();

        try map_for_line_0.put(0, &get_method_from_token);
        try map_for_line_0.put(1, &get_url_from_token);

        var map_for_line_accept = TokenInnerMap.init(allocator);
        errdefer map_for_line_accept.deinit();

        try map_for_line_accept.put(1, &get_mime_type_from_token);

        var outer_map = TokenOuterMap.init(allocator);

        try outer_map.put(RequestMapKey, map_for_line_0);
        try outer_map.put("Accept", map_for_line_accept);

        return outer_map;
    }

    // returns true if buffer end reached
    fn skip_ws(self: *RequestParser) bool {
        while (self.curr_ind < self.buffer.len and std.ascii.isWhitespace(self.get_curr_ch())) : (self.advance()) {
            if (self.get_curr_ch() == '\n') {
                self.curr_line_n += 1;
            }
        }

        return self.is_end_reached();
    }

    fn skip_ws_but_not_newline(self: *RequestParser) bool {
        while (self.curr_ind < self.buffer.len and self.get_curr_ch() != '\n' and std.ascii.isWhitespace(self.get_curr_ch())) : (self.advance()) {}

        return self.is_end_reached();
    }

    fn skip_token(self: *RequestParser) bool {
        while (self.curr_ind < self.buffer.len and !std.ascii.isWhitespace(self.get_curr_ch())) : (self.advance()) {}
        return self.is_end_reached();
    }

    fn slice_token(self: *RequestParser, rewind_back: bool) []const u8 {
        const start_ind: usize = self.curr_ind;
        while (self.curr_ind < self.buffer.len and !std.ascii.isWhitespace(self.get_curr_ch())) : (self.advance()) {}
        const token = self.buffer[start_ind..self.curr_ind];
        if (rewind_back) {
            self.curr_ind = start_ind;
        }
        return token;
    }

    // returns true if buffer end reached
    fn skip_curr_line(self: *RequestParser) bool {
        while (self.curr_ind < self.buffer.len and self.get_curr_ch() != '\n') : (self.advance()) {}
        const is_end = self.is_end_reached();

        if (!is_end) {
            self.advance();
            self.curr_line_n += 1;
        }

        return is_end;
    }

    inline fn get_curr_ch(self: RequestParser) u8 {
        return self.buffer[self.curr_ind];
    }

    inline fn advance(self: *RequestParser) void {
        self.curr_ind += 1;
    }

    inline fn is_end_reached(self: RequestParser) bool {
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

fn get_mime_type_from_token(token: []const u8, req: *Request) void {
    var mime_types_it = std.mem.splitScalar(u8, token, ',');

    while (mime_types_it.next()) |mime_type_str_full| {
        // reject ';q=n' part
        var mime_type_it = std.mem.splitScalar(u8, mime_type_str_full, ';');
        const mime_type_str = mime_type_it.first();
        if (MimeType.MapFromMimeStr.get(mime_type_str)) |mime_type| {
            if (req.mime_types.append(mime_type)) {
                continue;
            } else |err| {
                switch (err) {
                    else => {
                        io.error_log("Error while appending into array\n", .{});
                        return;
                    },
                }
            }
        }
    }
}

fn is_token_request(token: []const u8) bool {
    const method = MethodMap.get(token);
    return method != null;
}

fn log_token_dbg(token: []const u8, req: *Request) void {
    _ = req;
    io.error_log("token: {s}\n", .{token[0..]});
}
