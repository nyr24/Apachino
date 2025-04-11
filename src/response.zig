const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoHashMap;
const StaticStrMap = std.StaticStringMap;
const fmt = std.fmt;
const request = @import("request.zig");
const Request = request.Request;
const config = @import("server_conf.zig");
const Server = config.Server;
const io = @import("io.zig");
const OpenError = std.fs.Dir.OpenError;
const allocator = @import("env.zig").allocator;

pub const Response = struct {
    status: Status = undefined,
    mime_type: []const u8 = undefined,
    headers: []u8 = undefined,
    body: ?[]u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(req: Request, server_conf: Server) !Response {
        var response = Response{ .allocator = allocator };

        response.set_body(req, server_conf);
        try response.set_headers();

        return response;
    }

    pub fn deinit(self: Response) void {
        self.allocator.free(self.headers);
        if (self.body) |body_non_null| {
            self.allocator.free(body_non_null);
        }
    }

    fn set_headers(self: *Response) !void {
        var content_len: usize = 0;
        if (self.body) |body_non_null| {
            content_len = body_non_null.len;
        }

        self.headers = try fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {d} {s}" ++ "\nContent-Length: {d}" ++ "\nContent-Type: {s}\n" ++ "Connection: Closed\n\n",
            .{ self.status.code, self.status.message, content_len, self.mime_type },
        );
    }

    fn set_body(self: *Response, req: Request, server_conf: Server) void {
        if (server_conf.routes.get(req.url)) |route| {
            if (route.resource_path) |path_non_null| {
                const mime_type_enum = Response.extract_mime_type_from_extension(path_non_null);
                if (mime_type_enum) |mime_type_unwrapped| {
                    self.mime_type = MimeType.to_str(mime_type_unwrapped);
                } else {
                    // default mime type assigned
                    self.mime_type = MimeType.to_str(.application_octet_stream);
                }
                self.status = StatusType.get_status(.Ok);
                self.body = io.read_file(allocator, path_non_null) catch |err| {
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
        } else {
            self.status = StatusType.get_status(.NotFound);
        }
    }

    fn extract_mime_type_from_extension(resource_path: []const u8) ?MimeType {
        var last_dot_ind: usize = 0;
        var path_ind: usize = 0;

        while (path_ind < resource_path.len) : (path_ind += 1) {
            if (resource_path[path_ind] == '.') {
                last_dot_ind = path_ind;
            }
        }

        const extension = resource_path[last_dot_ind..];
        return MimeType.MapFromExtension.get(extension);
    }
};

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
    Accept,

    fn get_header_key(self: HeaderType) []const u8 {
        switch (self) {
            .ContentLength => return "Content-Length",
            .ContentType => return "Content-Type",
            .Connection => return "Connection",
            .Accept => return "Accept",
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

// https://www.iana.org/assignments/media-types/media-types.xhtml#model
pub const MimeType = enum {
    text,
    text_html,
    text_plain,
    text_css,
    text_javascript,
    text_calendar,

    application,
    application_json,
    application_xml,
    application_wasm,
    application_octet_stream,

    image,
    image_avif,
    image_png,
    image_apng,
    image_webp,
    image_svg_xml,
    image_jpeg,
    image_gif,

    video,
    video_mp4,
    video_ogg,
    video_webm,
    video_x_flv,

    audio,
    audio_mp4,
    audio_ogg,

    font,
    font_woff,
    font_woff2,
    font_ttf,
    font_otf,
    font_collection,

    model,
    model_3mf,
    model_gltf_binary,
    model_gltf_json,

    multipart,
    multipart_form_data,

    pub fn to_str(self: MimeType) []const u8 {
        switch (self) {
            .text => return "text/*",
            .text_html => return "text/html",
            .text_plain => return "text/plain",
            .text_css => return "text/css",
            .text_javascript => return "text/javascript",
            .text_calendar => return "text/calendar",

            .application => return "application/*",
            .application_json => return "application/json",
            .application_xml => return "application/xml",
            .application_wasm => return "application/wasm",
            .application_octet_stream => return "application/octet-stream",

            .image => return "image/*",
            .image_avif => return "image/avif",
            .image_png => return "image_png",
            .image_apng => return "image/apng",
            .image_webp => return "image/webp",
            .image_svg_xml => return "image/svg-xml",
            .image_jpeg => return "image/jpeg",
            .image_gif => return "image_gif",

            .video => return "video/*",
            .video_mp4 => return "video/mp4",
            .video_ogg => return "video/ogg",
            .video_webm => return "video/webm",
            .video_x_flv => return "video/x-flv",

            .audio => return "audio/*",
            .audio_mp4 => return "audio/mp4",
            .audio_ogg => return "audio/ogg",

            .font => return "font/*",
            .font_woff => return "font/woff",
            .font_woff2 => return "font/woff2",
            .font_ttf => return "font/ttf",
            .font_otf => return "font/otf",
            .font_collection => return "font/collection",

            .model => return "model/*",
            .model_3mf => return "model/3mf",
            .model_gltf_binary => return "model/gltf-binary",
            .model_gltf_json => return "model/gltf+json",

            .multipart => return "multipart/*",
            .multipart_form_data => return "multipart/form-data",
        }
    }

    pub const MapFromMimeStr = StaticStrMap(MimeType).initComptime(.{
        .{ "text/*", .text },
        .{ "text/html", .text_html },
        .{ "text/plain", .text_plain },
        .{ "text/css", .text_css },
        .{ "text/javascript", .text_javascript },
        .{ "text/calendar", .text_calendar },

        .{ "application/*", .application },
        .{ "application/json", .application_json },
        .{ "application/xml", .application_xml },
        .{ "application/wasm", .application_wasm },
        .{ "application/octet-stream", .application_octet_stream },

        .{ "image/*", .image },
        .{ "image/avif", .image_avif },
        .{ "image_png", .image_png },
        .{ "image/apng", .image_apng },
        .{ "image/webp", .image_webp },
        .{ "image/svg-xml", .image_svg_xml },
        .{ "image/jpeg", .image_jpeg },
        .{ "image/gif", .image_gif },

        .{ "video/*", .video },
        .{ "video/mp4", .video_mp4 },
        .{ "video/ogg", .video_ogg },
        .{ "video/webm", .video_webm },
        .{ "video/x-flv", .video_x_flv },

        .{ "audio/*", .audio },
        .{ "audio/mp4", .audio_mp4 },
        .{ "audio/ogg", .audio_ogg },

        .{ "font/*", .font },
        .{ "font/woff", .font_woff },
        .{ "font/woff2", .font_woff2 },
        .{ "font/ttf", .font_ttf },
        .{ "font/otf", .font_otf },
        .{ "font/collection", .font_collection },

        .{ "model/*", .model },
        .{ "model/3mf", .model_3mf },
        .{ "model/gltf-binary", .model_gltf_binary },
        .{ "model/gltf+json", .model_gltf_json },

        .{ "multipart/*", .multipart },
        .{ "multipart/form-data", .multipart_form_data },
    });

    const MapFromExtension = StaticStrMap(MimeType).initComptime(.{
        .{ ".html", .text_html },
        .{ ".txt", .text_plain },
        .{ ".css", .text_css },
        .{ ".js", .text_javascript },
        .{ ".ics", .text_calendar },

        .{ ".json", .application_json },
        .{ ".xml", .application_xml },
        .{ ".wasm", .application_wasm },
        // binary data
        .{ "", .application_octet_stream },
        .{ ".exe", .application_octet_stream },

        .{ ".avif", .image_avif },
        .{ ".png", .image_png },
        .{ ".apng", .image_apng },
        .{ ".webp", .image_webp },
        .{ ".svg", .image_svg_xml },
        .{ ".jpg", .image_jpeg },
        .{ ".jpeg", .image_jpeg },
        .{ ".gif", .image_gif },

        .{ ".mp4", .video_mp4 },
        .{ ".ogg", .video_ogg },
        .{ ".webm", .video_webm },
        .{ ".x-flv", .video_x_flv },

        .{ ".mp4", .audio_mp4 },
        .{ ".ogg", .audio_ogg },

        .{ ".woff", .font_woff },
        .{ ".woff2", .font_woff2 },
        .{ ".ttf", .font_ttf },
        .{ ".otf", .font_otf },
        .{ ".collection", .font_collection },

        .{ ".3mf", .model_3mf },
        .{ ".gltf-binary", .model_gltf_binary },
        .{ ".gltf+json", .model_gltf_json },

        .{ ".form-data", .multipart_form_data },
    });
};
