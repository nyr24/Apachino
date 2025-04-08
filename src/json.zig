const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.StringHashMap;
const stderr = std.io.getStdErr().writer();
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const server = @import("server_conf.zig");
const ServerConf = server.ServerConf;
const RouteConf = server.RouteConf;
const RequestMethod = @import("request.zig").Method;

// entry point for config parsing
pub fn parse_config(contents: []const u8) !JsonParsedRepr {
    var conf_parser = JsonParser.init(contents);
    const parsed_json = try conf_parser.parse();
    return parsed_json;
}

const JsonField = []const u8;
pub const JsonValueTag = enum {
    String,
    Number,
    Bool,
    Table,
    Array,
    Null,
    Undefined,

    pub fn to_str(self: JsonValueTag) []const u8 {
        switch (self) {
            .String => return "String",
            .Number => return "Number",
            .Bool => return "Bool",
            .Table => return "Table",
            .Array => return "Array",
            .Null => return "Null",
            .Undefined => return "Undefined",
        }
    }
};

const JsonBoolLiteral = enum {
    True,
    False,
};

pub const JsonValue = union(JsonValueTag) {
    String: []const u8,
    Number: i32,
    Bool: bool,
    Table: JsonTable,
    Array: JsonArray,
    Null: u8,
    Undefined: u8,
};

const JsonTable = HashMap(JsonValue);
const JsonArray = ArrayList(JsonValue);

pub const JsonParsedRepr = JsonTable;

const ConfigParseErr = error{
    RouteNotFullyDefined,
    ConfigEndReachedEarly,
};

const JsonParseErr = ConfigParseErr;

const JsonParser = struct {
    buffer: []const u8,
    curr_ind: usize = 0,
    curr_line_n: usize = 0,

    pub fn init(buffer: []const u8) JsonParser {
        return JsonParser{ .buffer = buffer };
    }

    pub fn parse(self: *JsonParser) JsonParseErr!JsonParsedRepr {
        self.skip_ws(true);
        if (!self.check_curr_ch('{', true)) {
            self.throw_unexpected_token("expected a '{' symbol as opening of json table");
        }

        const json_parsed = self.parse_json_table();
        self.skip_ws(false);

        switch (json_parsed) {
            .Table => |json_parsed_| {
                if (self.is_end_reached()) {
                    return json_parsed_;
                } else {
                    return JsonParseErr.ConfigEndReachedEarly;
                }
            },
            else => unreachable,
        }

        return JsonParseErr.ConfigEndReachedEarly;
    }

    fn parse_json_value(self: *JsonParser) JsonValue {
        self.skip_ws(true);

        switch (self.get_curr_ch()) {
            '{' => {
                self.advance();
                return self.parse_json_table();
            },
            '[' => {
                self.advance();
                return self.parse_json_arr();
            },
            '\"' => {
                return self.parse_json_string();
            },
            else => {
                const ch = self.get_curr_ch();
                if (std.ascii.isDigit(ch)) {
                    return self.parse_json_number();
                } else if (JsonParser.is_bool_start(ch)) {
                    if (ch == 't') {
                        const bool_val = self.parse_json_bool(.True);
                        if (bool_val) |non_null| {
                            return non_null;
                        } else {
                            self.throw_unexpected_token("maybe you mean true?");
                        }
                    } else {
                        const bool_val = self.parse_json_bool(.False);
                        if (bool_val) |non_null| {
                            return non_null;
                        } else {
                            self.throw_unexpected_token("maybe you mean false?");
                        }
                    }
                } else if (JsonParser.is_null_start(ch)) {
                    const null_val = self.parse_json_null();
                    if (null_val) |truly_null| {
                        return truly_null;
                    } else {
                        self.throw_unexpected_token("maybe you mean null?");
                    }
                } else if (JsonParser.is_undefined_start(ch)) {
                    const undef_val = self.parse_json_undefined();
                    if (undef_val) |truly_undef| {
                        return truly_undef;
                    } else {
                        self.throw_unexpected_token("maybe you mean undefined?");
                    }
                }
            },
        }

        unreachable;
    }

    fn parse_json_table(self: *JsonParser) JsonValue {
        var json_table = JsonValue{ .Table = JsonTable.init(allocator) };

        while (true) {
            self.skip_ws(true);

            const json_field = self.parse_json_field();
            const json_val = self.parse_json_value();

            switch (json_table) {
                .Table => |*_json_table| {
                    _json_table.*.put(json_field, json_val) catch unreachable;
                },
                else => unreachable,
            }

            self.skip_ws(true);
            if (self.check_curr_ch(',', true)) {
                continue;
            } else if (self.check_curr_ch('}', true)) {
                return json_table;
            } else if (self.is_end_reached()) {
                self.throw_end_reached_early("json table was not terminated, expected '}'");
            }
        }
    }

    fn parse_json_arr(self: *JsonParser) JsonValue {
        var json_arr = JsonValue{ .Array = JsonArray.initCapacity(allocator, 5) catch unreachable };

        while (true) {
            self.skip_ws(true);
            const json_val = self.parse_json_value();

            switch (json_arr) {
                .Array => |*json_arr_| {
                    json_arr_.*.append(json_val) catch unreachable;
                },
                else => unreachable,
            }

            self.skip_ws(true);
            if (self.check_curr_ch(',', true)) {
                continue;
            } else if (self.check_curr_ch(']', true)) {
                return json_arr;
            } else if (self.is_end_reached()) {
                self.throw_end_reached_early(null);
            }
        }
    }

    fn parse_json_field(self: *JsonParser) JsonField {
        const str_literal = self.parse_json_str_literal();
        self.skip_ws(true);
        if (!self.check_curr_ch(':', true)) {
            self.throw_unexpected_token("expected ':' after field declaration");
        }

        return str_literal;
    }

    fn parse_json_string(self: *JsonParser) JsonValue {
        const str_literal = self.parse_json_str_literal();
        const json_val: JsonValue = .{ .String = str_literal };
        return json_val;
    }

    fn parse_json_str_literal(self: *JsonParser) []const u8 {
        if (!self.check_curr_ch('\"', true)) {
            self.throw_unexpected_token(null);
        }

        const str_start: usize = self.curr_ind;
        self.match_any_until('\"', true);

        if (self.is_end_reached()) {
            self.throw_end_reached_early(null);
        }

        const str: []const u8 = self.buffer[str_start..self.curr_ind];

        if (!self.check_curr_ch('\"', true)) {
            self.throw_unexpected_token("expected '\"' at the end of json string");
        }

        return str;
    }

    fn parse_json_number(self: *JsonParser) JsonValue {
        const start_ind = self.curr_ind;
        self.match_any_for_callback(std.ascii.isDigit, true);
        if (std.fmt.parseInt(i32, self.buffer[start_ind..self.curr_ind], 10)) |parsed_number| {
            self.advance();
            return JsonValue{ .Number = parsed_number };
        } else |err| {
            switch (err) {
                error.Overflow => {
                    std.debug.print("Overflow, when trying to parse integer: {s}", .{self.buffer[start_ind..self.curr_ind]});
                    std.process.exit(1);
                },
                error.InvalidCharacter => {
                    self.throw_unexpected_token("expected a value of Number type");
                },
                else => unreachable,
            }
        }
    }

    fn parse_json_bool(self: *JsonParser, bool_val: JsonBoolLiteral) ?JsonValue {
        switch (bool_val) {
            .True => {
                const match = self.match_expected_seq("true", true, true, true);
                if (match != null) {
                    self.advance();
                    return JsonValue{ .Bool = true };
                } else {
                    return null;
                }
            },
            .False => {
                const match = self.match_expected_seq("false", true, true, true);
                if (match != null) {
                    self.advance();
                    return JsonValue{ .Bool = false };
                } else {
                    return null;
                }
            },
        }
    }

    fn parse_json_null(self: *JsonParser) ?JsonValue {
        const null_parsed = self.match_expected_seq("null", true, true, true);
        if (null_parsed != null) {
            self.advance();
            return JsonValue{ .Null = 0 };
        } else {
            return null;
        }
    }

    fn parse_json_undefined(self: *JsonParser) ?JsonValue {
        const undef_parsed = self.match_expected_seq("undefined", true, true, true);
        if (undef_parsed != null) {
            self.advance();
            return JsonValue{ .Undefined = 0 };
        } else {
            return null;
        }
    }

    fn match_expected_seq(self: *JsonParser, expected_seq: []const u8, skip_ws_before: bool, throw_if_not_match: bool, throw_if_end_reached: bool) ?[]const u8 {
        if (skip_ws_before) {
            self.skip_ws(true);
        }

        const start_ind = self.curr_ind;
        var expected_ind: usize = 0;

        while (self.curr_ind < self.buffer.len and expected_ind < expected_seq.len and self.get_curr_ch() == expected_seq[expected_ind]) {
            self.advance();
            expected_ind += 1;
        }

        if (expected_ind == expected_seq.len) {
            // success
            return self.buffer[start_ind..self.curr_ind];
        } else {
            if (self.is_end_reached() and throw_if_end_reached) {
                self.curr_ind = start_ind;
                self.throw_end_reached_early(expected_seq);
            } else {
                self.curr_ind = start_ind;
                if (throw_if_not_match) {
                    self.throw_unexpected_token(expected_seq);
                }
                return null;
            }
        }
    }

    // returns true if buffer end reached
    inline fn skip_ws(self: *JsonParser, throw_if_end_reached: bool) void {
        while (self.curr_ind < self.buffer.len and (std.ascii.isWhitespace(self.get_curr_ch()) or self.check_curr_ch('/', false))) : (self.advance()) {
            if (self.get_curr_ch() == '\n') {
                self.curr_line_n += 1;
            }
        }

        if (self.is_end_reached() and throw_if_end_reached) {
            self.throw_end_reached_early(null);
        }
    }

    inline fn match_any_until(self: *JsonParser, until_ch: u8, throw_if_end_reached: bool) void {
        while (self.curr_ind < self.buffer.len and self.get_curr_ch() != until_ch) : (self.advance()) {
            if (self.get_curr_ch() == '\n') {
                self.curr_line_n += 1;
            }
        }

        if (self.is_end_reached() and throw_if_end_reached) {
            self.throw_end_reached_early(null);
        }
    }

    inline fn match_any_for_callback(self: *JsonParser, callback: *const fn (u8) bool, throw_if_end_reached: bool) void {
        while (self.curr_ind < self.buffer.len and callback(self.get_curr_ch())) : (self.advance()) {
            if (self.get_curr_ch() == '\n') {
                self.curr_line_n += 1;
            }
        }

        if (self.is_end_reached() and throw_if_end_reached) {
            self.throw_end_reached_early(null);
        }
    }

    inline fn is_bool_start(ch: u8) bool {
        return ch == 't' or ch == 'f';
    }

    inline fn is_null_start(ch: u8) bool {
        return ch == 'n';
    }

    inline fn is_undefined_start(ch: u8) bool {
        return ch == 'u';
    }

    inline fn get_curr_ch(self: JsonParser) u8 {
        return self.buffer[self.curr_ind];
    }

    inline fn check_curr_ch(self: *JsonParser, ch: u8, advance_if_success: bool) bool {
        const success = self.get_curr_ch() == ch;
        if (success and advance_if_success) {
            self.advance();
        }
        return success;
    }

    inline fn advance(self: *JsonParser) void {
        self.curr_ind += 1;
    }

    inline fn is_end_reached(self: JsonParser) bool {
        return self.curr_ind >= self.buffer.len;
    }

    inline fn throw_end_reached_early(self: JsonParser, expect_message: ?[]const u8) void {
        if (expect_message) |expect_message_no_null| {
            stderr.print("End of config is reached early, line {d},\n\t{s}", .{ self.curr_line_n, expect_message_no_null }) catch unreachable;
        } else {
            stderr.print("End of config is reached early, line {d}", .{self.curr_line_n}) catch unreachable;
        }
        std.process.exit(1);
    }

    inline fn throw_unexpected_token(self: *JsonParser, expect_message: ?[]const u8) void {
        const start_ind = self.curr_ind;
        self.match_any_for_callback(std.ascii.isAlphanumeric, false);
        const unexpected_seq = self.buffer[start_ind..self.curr_ind];

        if (expect_message) |expect_message_no_null| {
            stderr.print("Unexpected token at line {d}: {s},\n\t{s}", .{ self.curr_line_n, unexpected_seq, expect_message_no_null }) catch unreachable;
        } else {
            stderr.print("Unexpected token at line {d}: {s}", .{ self.curr_line_n, unexpected_seq }) catch unreachable;
        }
        std.process.exit(1);
    }

    inline fn debug_print_curr(self: JsonParser) void {
        std.debug.print("{c}\n", .{self.get_curr_ch()});
    }

    inline fn debug_print_seq(self: JsonParser, offset: usize) void {
        const end_ind = self.curr_ind + offset;
        std.debug.print("{s}\n", .{self.buffer[self.curr_ind..end_ind]});
    }
};
