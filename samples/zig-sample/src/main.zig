const std = @import("std");
const oc = @import("root");

const lerp = std.math.lerp;

const Vec2 = oc.vec2;
const Mat2x3 = oc.mat2x3;
const Str8 = oc.str8;

var allocator = std.heap.wasm_allocator;

var surface: oc.surface = undefined;
var canvas: struct { ctx: oc.canvas_context, renderer: oc.canvas_renderer } = undefined;
var font: oc.font = undefined;
var orca_image: oc.image = undefined;
var gradient_image: oc.image = undefined;

var counter: u32 = 0;
var last_seconds: f64 = 0;
var frame_size: Vec2 = .{ .x = 0, .y = 0 };

var rotation_demo: f32 = 0;

pub fn onInit() !void {
    oc.window_set_title(oc.to_str8(@constCast("zig sample")));
    oc.window_set_size(.{ .x = 480, .y = 640 });

    canvas.renderer = oc.canvas_renderer_create();
    surface = oc.canvas_surface_create(canvas.renderer);

    const scale = oc.surface_contents_scaling(surface);
    oc.log.info("surface scaling: {d:.2} {d:.2}", .{ scale.x, scale.y }, @src());

    oc.assert(oc.canvas_renderer_is_nil(oc.canvas_renderer_nil()), "nil canvas should be nil", .{}, @src());
    oc.assert(!oc.canvas_renderer_is_nil(canvas.renderer), "created canvas should not be nil", .{}, @src());

    const ranges = [5]oc.unicode_range{
        .{ .firstCodePoint = 0x0000, .count = 127 }, // BASIC_LATIN
        .{ .firstCodePoint = 0x0080, .count = 127 }, // C1_CONTROLS_AND_LATIN_1_SUPPLEMENT
        .{ .firstCodePoint = 0x0100, .count = 127 }, // LATIN_EXTENDED_A
        .{ .firstCodePoint = 0x0180, .count = 207 }, // LATIN_EXTENDED_B
        .{ .firstCodePoint = 0xfff0, .count = 15 }, //  SPECIALS
    };
    font = oc.font_create_from_path(oc.to_str8(@constCast("/zig.ttf")), ranges.len, @constCast(&ranges));
    oc.assert(oc.font_is_nil(oc.font_nil()), "nil font should be nil", .{}, @src());
    oc.assert(!oc.font_is_nil(font), "created font should not be nil", .{}, @src());

    orca_image = oc.image_create_from_path(canvas.renderer, oc.to_str8(@constCast("/orca_jumping.jpg")), false);
    oc.assert(oc.image_is_nil(oc.image_nil()), "nil image should be nil", .{}, @src());
    oc.assert(!oc.image_is_nil(orca_image), "created image should not be nil", .{}, @src());

    // generate a gradient and upload it to an image
    {
        const width = 256;
        const height = 128;

        const tl: oc.color = .{ .r = 70.0 / 255.0, .g = 13.0 / 255.0, .b = 108.0 / 255.0, .a = 0, .colorSpace = .COLOR_SPACE_RGB };
        const bl: oc.color = .{ .r = 251.0 / 255.0, .g = 167.0 / 255.0, .b = 87.0 / 255.0, .a = 0, .colorSpace = .COLOR_SPACE_RGB };
        const tr: oc.color = .{ .r = 48.0 / 255.0, .g = 164.0 / 255.0, .b = 219.0 / 255.0, .a = 0, .colorSpace = .COLOR_SPACE_RGB };
        const br: oc.color = .{ .r = 151.0 / 255.0, .g = 222.0 / 255.0, .b = 150.0 / 255.0, .a = 0, .colorSpace = .COLOR_SPACE_RGB };

        var pixels: [width * height]u32 = undefined;
        for (0..height) |y| {
            for (0..width) |x| {
                const h: f32 = @floatFromInt(height - 1);
                const w: f32 = @floatFromInt(width - 1);
                const y_norm: f32 = @as(f32, @floatFromInt(y)) / h;
                const x_norm: f32 = @as(f32, @floatFromInt(x)) / w;

                const tl_weight = (1 - x_norm) * (1 - y_norm);
                const bl_weight = (1 - x_norm) * y_norm;
                const tr_weight = x_norm * (1 - y_norm);
                const br_weight = x_norm * y_norm;

                const color = oc.color_rgba(
                    tl_weight * tl.r + bl_weight * bl.r + tr_weight * tr.r + br_weight * br.r,
                    tl_weight * tl.g + bl_weight * bl.g + tr_weight * tr.g + br_weight * br.g,
                    tl_weight * tl.b + bl_weight * bl.b + tr_weight * tr.b + br_weight * br.b,
                    1,
                );
                pixels[y * width + x] = packRgba8(color);
            }
        }

        gradient_image = oc.image_create_from_rgba8(canvas.renderer, width, height, @ptrCast(&pixels));
    }

    try testFileApis();
}

/// pack 0-1 RGBAf32 color into a u32
fn packRgba8(color: oc.color) u32 {
    var result: u32 = 0;
    const c = &color;
    result |= @as(u32, @intFromFloat(c.r * 255.0)) << 0;
    result |= @as(u32, @intFromFloat(c.g * 255.0)) << 8;
    result |= @as(u32, @intFromFloat(c.b * 255.0)) << 16;
    result |= @as(u32, @intFromFloat(c.a * 255.0)) << 24;
    return result;
}

pub fn onResize(width: u32, height: u32) void {
    frame_size = .{ .x = @floatFromInt(width), .y = @floatFromInt(height) };
    const surface_size = oc.surface_get_size(surface);
    oc.log.info("frame resize: {d:.2}, {d:.2}, surface size: {d:.2} {d:.2}", .{ frame_size.x, frame_size.y, surface_size.x, surface_size.y }, @src());
}

pub fn onMouseDown(button: oc.mouse_button) void {
    oc.log.info("mouse down! {}", .{button}, @src());
}

pub fn onMouseUp(button: oc.mouse_button) void {
    oc.log.info("mouse up! {}", .{button}, @src());
}

pub fn onMouseWheel(dx: f32, dy: f32) void {
    oc.log.info("mouse wheel! dx: {d:.2}, dy: {d:.2}", .{ dx, dy }, @src());
}

pub fn onKeyDown(scan: oc.scan_code, key: oc.key_code) void {
    oc.log.info("key down: {} {}", .{ scan, key }, @src());
}

pub fn onKeyUp(scan: oc.scan_code, key: oc.key_code) void {
    oc.log.info("key up: {s} {s}", .{ @tagName(scan), @tagName(key) }, @src());

    switch (key) {
        .KEY_ESCAPE => oc.request_quit(),
        .KEY_B => oc.abort("aborting", .{}, @src()),
        .KEY_A => oc.assert(false, "test assert failed", .{}, @src()),
        .KEY_W => oc.log.warn("logging a test warning", .{}, @src()),
        .KEY_E => oc.log.err("logging a test error", .{}, @src()),
        else => {},
    }
}

pub fn onFrameRefresh() !void {
    counter += 1;

    const secs: f64 = oc.ui_frame_time();

    if (last_seconds != @floor(secs)) {
        last_seconds = @floor(secs);
        oc.log.info("seconds since Jan 1, 1970: {d:.0}", .{secs}, @src());
    }

    _ = oc.canvas_context_select(canvas.ctx);

    {
        const c1: oc.color = .{ .r = 0.05, .g = 0.05, .b = 0.05, .a = 1.0, .colorSpace = .COLOR_SPACE_RGB };
        const c2: oc.color = .{ .r = 0.05, .g = 0.05, .b = 0.05, .a = 1.0, .colorSpace = .COLOR_SPACE_RGB };
        oc.set_color_rgba(c1.r, c1.g, c1.b, c1.a);
        oc.assert(std.meta.eql(oc.get_color(), c1), "color should be what we set", .{}, @src());
        oc.set_color(c2);
        oc.assert(std.meta.eql(oc.get_color(), c2), "color should be what we set", .{}, @src());
        oc.clear();

        oc.set_tolerance(1);
        oc.assert(oc.get_tolerance() == 1, "tolerance should be 1", .{}, @src());
        oc.set_joint(.JOINT_BEVEL);
        oc.assert(oc.get_joint() == .JOINT_BEVEL, "joint should be what we set", .{}, @src());
        oc.set_cap(.CAP_SQUARE);
        oc.assert(oc.get_cap() == .CAP_SQUARE, "cap should be what we set", .{}, @src());
    }

    {
        const translation: oc.mat2x3 = .{ .m = [_]f32{ 1, 0, 50, 0, 1, 50 } };
        oc.matrix_push(translation);
        defer oc.matrix_pop();

        oc.assert(std.meta.eql(oc.matrix_top(), translation), "top of matrix stack should be what we pushed", .{}, @src());
        oc.set_width(1);
        oc.assert(oc.get_width() == 1, "width should be 1", .{}, @src());
        oc.rectangle_fill(50, 0, 10, 10);
        oc.rectangle_stroke(70, 0, 10, 10);
        oc.rounded_rectangle_fill(90, 0, 10, 10, 3);
        oc.rounded_rectangle_stroke(110, 0, 10, 10, 3);

        const green: oc.color = .{ .r = 0.05, .g = 1, .b = 0.05, .a = 1, .colorSpace = .COLOR_SPACE_RGB };
        oc.set_color(green);

        oc.ellipse_fill(140, 5, 10, 5);
        oc.ellipse_stroke(170, 5, 10, 5);
        oc.circle_fill(195, 5, 5);
        oc.circle_stroke(215, 5, 5);

        oc.arc(235, 5, 5, std.math.pi, 0);
        oc.stroke();

        oc.arc(260, 5, 5, std.math.pi, 0);
        oc.fill();

        oc.move_to(0, 0);
        oc.assert(std.meta.eql(oc.vec2{ .x = 0, .y = 0 }, oc.get_position()), "pos should be zero after moving there", .{}, @src());
    }

    {
        rotation_demo += 0.03;

        const rot = oc.mat2x3_rotate(rotation_demo);
        const trans = oc.mat2x3_translate(335, 55);
        oc.matrix_push(oc.mat2x3_mul_m(trans, rot));
        defer oc.matrix_pop();

        oc.rectangle_fill(-5, -5, 10, 10);
    }

    {
        const scratch_scope = oc.scratch_begin();
        defer oc.arena_scope_end(scratch_scope);

        const scratch: *oc.arena = scratch_scope.arena;

        const str1: []const u8 = oc.str8_list_collate(
            scratch,
            &[_][]const u8{ "Hello", "from", "Zig!" },
            ">> ",
            " ",
            " <<",
        );

        var str2_list: oc.str8_list = .{
            .list = undefined,
            .eltCount = 0,
            .len = 0,
        };
        oc.list_init(&str2_list.list);

        oc.str8_list_push(scratch, &str2_list, oc.to_str8(@constCast("All")));
        str2_list.pushf(scratch, &str2_list, "your %s", "base!!");

        oc.assert(str2_list.contains("All"), "str2_list should have the string we just pushed", .{}, @src());

        {
            const elt_first = str2_list.list.first;
            const elt_last = str2_list.list.last;
            oc.assert(elt_first != null, "list checks", .{}, @src());
            oc.assert(elt_last != null, "list checks", .{}, @src());
            oc.assert(elt_first != elt_last, "list checks", .{}, @src());
            oc.assert(elt_first.?.next != null, "list checks", .{}, @src());
            oc.assert(elt_first.?.prev == null, "list checks", .{}, @src());
            oc.assert(elt_last.?.next == null, "list checks", .{}, @src());
            oc.assert(elt_last.?.prev != null, "list checks", .{}, @src());
            oc.assert(elt_first.?.next != elt_last, "list checks", .{}, @src());
            oc.assert(elt_last.?.prev != elt_first, "list checks", .{}, @src());
        }

        const str2: []const u8 = str2_list.collate(scratch, "<< ", "-", " >>");

        const font_size = 18;
        const text_metrics = font.textMetrics(font_size, str1);
        const text_rect = text_metrics.ink;

        const center_x = frame_size.x / 2;
        const text_begin_x = center_x - text_rect.w / 2;

        Mat2x3.push(Mat2x3.translate(text_begin_x, 100));
        defer Mat2x3.pop();

        oc.set_color_rgba(1.0, 0.05, 0.05, 1.0);
        oc.set_font(font);
        oc.set_font_size(font_size);
        oc.move_to(0, 0);
        oc.text_outlines(str1);
        oc.move_to(0, 35);
        oc.text_outlines(str2);
        oc.fill();
    }

    {
        var scratch_scope = oc.Arena.scratchBegin();
        defer scratch_scope.end();

        const scratch: *oc.Arena = scratch_scope.arena;

        var strings_array = std.ArrayList([]const u8).init(allocator);
        defer strings_array.deinit();
        try strings_array.append("This ");
        try strings_array.append("is");
        try strings_array.append(" |a");
        try strings_array.append("one-word string that ");
        try strings_array.append(" |  has");
        try strings_array.append(" no ");
        try strings_array.append("    spaces i");
        try strings_array.append("n it");

        var single_string = std.ArrayList(u8).init(allocator);
        for (strings_array.items) |str| {
            try single_string.appendSlice(str);
        }

        const big_string = Str8.fromSlice(single_string.items);
        const separators = [_][]const u8{ " ", "|", "-" };
        var strings: oc.Str8List = Str8.split(big_string.slice(), scratch, &separators);
        const collated: []const u8 = strings.join(scratch);

        oc.set_font_size(12);
        oc.move_to(0, 170);
        oc.text_outlines(collated);
        oc.fill();
    }

    {
        const orca_size = orca_image.size();

        {
            const trans = Mat2x3.translate(0, 200);
            const scale = Mat2x3.scaleUniform(0.25);
            Mat2x3.push(Mat2x3.mulM(trans, scale));
            defer Mat2x3.pop();

            orca_image.draw(oc.Rect.xywh(0, 0, orca_size.x, orca_size.y));

            var half_size = orca_size;
            half_size.x /= 2;
            orca_image.drawRegion(oc.Rect.xywh(0, 0, half_size.x, half_size.y), oc.Rect.xywh(orca_size.x + 10, 0, half_size.x, half_size.y));
        }

        {
            const x_offset = orca_size.x * 0.25 + orca_size.x * 0.25 * 0.5 + 5;
            const gradient_size = gradient_image.size();

            const trans = Mat2x3.translate(x_offset, 200);
            const scale = Mat2x3.scaleUniform((orca_size.y * 0.25) / gradient_size.y);
            Mat2x3.push(Mat2x3.mulM(trans, scale));
            defer Mat2x3.pop();

            gradient_image.draw(oc.Rect.xywh(0, 0, gradient_size.x, gradient_size.y));
        }
    }

    surface.select();
    canvas.render();
    surface.present();
}

pub fn onTerminate() void {
    font.destroy();
    canvas.destroy();

    oc.log.info("byebye {}", .{counter}, @src());
}

fn oneMinusLerp(a: anytype, b: anytype, t: anytype) @TypeOf(a, b, t) {
    return 1.0 - lerp(a, b, t);
}

fn testFileApis() !void {
    var cwd = try oc.File.open("/", oc.File.AccessFlags.readonly(), oc.File.OpenFlags.none());
    oc.assert(cwd.isNil() == false, "file should be valid", .{}, @src());
    defer cwd.close();

    var orca_jumping_file = try oc.File.open("/orca_jumping.jpg", oc.File.AccessFlags.readonly(), oc.File.OpenFlags.none());
    oc.assert(orca_jumping_file.isNil() == false, "file should be valid", .{}, @src());
    orca_jumping_file.close();

    orca_jumping_file = try oc.File.openAt(cwd, "orca_jumping.jpg", oc.File.AccessFlags.readonly(), oc.File.OpenFlags.none());
    oc.assert((try orca_jumping_file.getStatus()).type == .Regular, "status API works", .{}, @src());
    oc.assert(try orca_jumping_file.getSize() > 0, "size API works", .{}, @src());
    oc.assert(orca_jumping_file.isNil() == false, "file should be valid", .{}, @src());

    var tmp_image = oc.image.createFromFile(surface, orca_jumping_file, .NoFlip);
    oc.assert(tmp_image.isNil() == false, "image loaded from file should not be nil", .{}, @src());
    tmp_image.destroy();
    orca_jumping_file.close();

    const temp_file_contents = "hello world!";
    const temp_file_path = "/temp_file.txt";
    {
        var tmp_file = try oc.File.open(temp_file_path, oc.File.AccessFlags.readwrite(), oc.File.OpenFlags{ .create = true });
        defer tmp_file.close();

        oc.assert(tmp_file.isNil() == false, "file should be valid", .{}, @src());
        oc.assert(try tmp_file.pos() == 0, "new file shouldn't have anything in it yet", .{}, @src());

        var writer = tmp_file.writer();
        const written = try writer.write(temp_file_contents);
        oc.assert(written == temp_file_contents.len, "should have written some bytes.", .{}, @src());
    }

    {
        var tmp_file = try oc.File.open(temp_file_path, oc.File.AccessFlags.readwrite(), oc.File.OpenFlags{ .create = true });
        defer tmp_file.close();

        _ = try tmp_file.seek(0, .Set);
        oc.assert(try tmp_file.pos() == 0, "should be back at the beginning of the file", .{}, @src());

        var buffer: [temp_file_contents.len]u8 = undefined;
        var reader = tmp_file.reader();
        _ = try reader.read(&buffer);
        oc.assert(std.mem.eql(u8, temp_file_contents, &buffer), "should have read what was in the original buffer", .{}, @src());
    }
}
