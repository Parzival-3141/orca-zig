//! This script will generate the Zig bindings for the Orca api using an api.json file.

const std = @import("std");
const json = std.json;
const assert = std.debug.assert;
const AnyWriter = std.io.AnyWriter;

// api.json wishlist (in order of importance):
// - format documentation
// - format and api versioning!!!
// - specify pointer types (single/multi-item, nullable, mutable, etc...)
// - change module brief to doc for consistency
// - remove unnamed enums, create a dedicated "constant" kind instead
// - missing OC_UNICODE_RANGE values
// - missing oc_clock_time
// - make OC_UI_STYLE a proper enum
// - oc_pool and oc_window are missing typename entries
// - oc_ui_box is duplicated
// - OC_OC_IO_ERROR typo?
// - flag enum types should be differentiated from normal enums
// - flag enum types should use the correct backing values (i.e. oc_file_open_flags_enum should use u16 not u32)

// TODO using @constCast all the time is annoying and error prone.
// Instead default [*c]u8 pointers to [*:0]const u8 and check against an exceptions list in Quirks.

// NEW PLAN !!!
// NEW PLAN !!!
// NEW PLAN !!!
// NEW PLAN !!!
// We're gonna maintain the bindings manually. This will result in a higher quality API in exchange for more work upfront.
// However the bindings will still use api.json as a ground truth, targeting a specific version/commit. Whenever api.json is
// updated you can use the diff from the current version to perform updates.

// By using api.json in favor of orca.h, we're able to upstream any improvements that aide in creating idiomatic bindings,
// benefitting other consumers/binding projects as well.

// Doing it this way eases maintenance (incremental patches, clear update path, can add CI) and improves API quality for everyone.

const Kind = enum {
    @"enum",
    @"enum-constant",
    @"struct",
    @"union",
    @"variadic-param",
    array,
    bool,
    char,
    f32,
    f64,
    i32,
    i64,
    macro,
    module,
    /// type reference
    namedType,
    pointer,
    proc,
    size_t,
    /// type declaration
    typename,
    u16,
    u32,
    u64,
    u8,
    va_list,
    void,
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    const api_path = args.next() orelse return fatal("Expected api.json file argument", .{});
    const output_path = args.next() orelse return fatal("Expected output file argument", .{});

    const api_src = try std.fs.cwd().readFileAlloc(allocator, api_path, 1024 * 1024);

    var diag: json.Diagnostics = .{};
    var scanner = json.Scanner.initCompleteInput(allocator, api_src);
    scanner.enableDiagnostics(&diag);

    const api = json.parseFromTokenSourceLeaky(json.Value, allocator, &scanner, .{}) catch |err| {
        const line_start = diag.line_start_cursor +% 1;
        const line_end = std.mem.indexOfScalarPos(u8, api_src, line_start, '\n') orelse api_src.len;

        const token_start = diag.getByteOffset();

        const max_window_size = 80;
        const window_start = @max(line_start, token_start -| max_window_size / 2);
        const window_end = @min(line_end, token_start + max_window_size / 2);

        var buf = [_]u8{' '} ** max_window_size;
        buf[token_start - window_start] = '^';

        return fatal("{s}:{d}:{d}: {s}\n{s}\n{s}", .{
            api_path,
            diag.getLine(),
            diag.getColumn(),
            @errorName(err),
            api_src[window_start..window_end],
            &buf,
        });
    };

    const output = try std.fs.cwd().createFile(output_path, .{});
    defer output.close();

    var bw = std.io.bufferedWriter(output.writer());
    const writer = bw.writer();

    for (api.array.items) |module| {
        assert(expectKind(module.object) == .module);
        try handleModule(module.object, writer.any(), 0);
    }

    try bw.flush();

    return 0;
}

const WriteError = anyerror;

fn handleModule(module: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    const name = expectField(module, "name");
    const brief = expectField(module, "brief");

    try writer.print(
        \\
        \\//------------------------------------------------------------------------------------------
        \\// [{s}] {s}
        \\//------------------------------------------------------------------------------------------
        \\
        \\
    , .{ name.string, brief.string });

    try Quirks.handleModule(name.string, writer);

    const contents = expectField(module, "contents");
    for (contents.array.items) |value| {
        const obj_kind = expectKind(value.object);
        switch (obj_kind) {
            .module => try handleModule(value.object, writer, depth),
            .macro => try handleMacro(value.object, writer, depth),
            .proc => try handleProc(value.object, writer, depth),
            .typename => try handleTypename(value.object, writer, depth),
            else => try defaultHandler(value.object, writer, depth),
        }
        try writer.writeByte('\n');
    }
}

/// Emit modules as namespace structs
fn handleModuleNamespaced(module: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    const name = expectField(module, "name");
    const brief = expectField(module, "brief");

    try writer.print("/// {s}\n", .{brief.string});
    try writer.writeByteNTimes(' ', depth * 4);
    try writer.print("pub const @\"{s}\" = struct {{\n", .{name.string});

    const contents = expectField(module, "contents");
    for (contents.array.items) |value| {
        const obj_kind = expectKind(value.object);

        try writer.writeByteNTimes(' ', (1 + depth) * 4);
        switch (obj_kind) {
            .module => try handleModule(value.object, writer, depth + 1),
            .macro => try handleMacro(value.object, writer, depth + 1),
            .proc => try handleProc(value.object, writer, depth + 1),
            .typename => try handleTypename(value.object, writer, depth + 1),
            else => try defaultHandler(value.object, writer, depth + 1),
        }
        try writer.writeByte('\n');
    }
    try writer.writeByteNTimes(' ', depth * 4);
    try writer.writeAll("};\n");
}

fn handleMacro(macro: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    if (macro.get("doc")) |doc| {
        try handleDocComment(doc, writer, depth);
    }
    const name = expectField(macro, "name");
    try writer.print(
        "pub const {s} = @compileError(\"TODO: translate macro\");",
        .{name.string}, // not formatting these names so they're easier to grep when we eventually handle macros
    );
}

fn handleProc(proc: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    // [doc-comment]
    // (pub extern)|*const fn [name](([doc-comment] param: type,)*) callconv(.C) type;

    const ret = expectField(proc, "return");
    const params = expectField(proc, "params");

    const proc_name = proc.get("name");
    if (proc_name) |name| {
        if (proc.get("doc")) |doc| {
            try handleDocComment(doc, writer, depth);
        }
        try writer.print("pub const {s} = {s};\n", .{ fmtDeclName(name.string), name.string });
        try writer.writeByteNTimes(' ', depth * 4);
        try writer.print("extern fn {s}(", .{name.string});
    } else {
        try writer.writeAll("*const fn (");
    }

    for (params.array.items) |param| {
        try writer.writeByte('\n');
        try writer.writeByteNTimes(' ', (1 + depth) * 4);
        if (param.object.get("doc")) |param_doc| {
            try handleDocComment(param_doc, writer, depth + 1);
        }

        const name = expectField(param.object, "name");
        const _type = expectField(param.object, "type");

        if (strEql(name.string, "...")) {
            assert(expectKind(_type.object) == .@"variadic-param");
            try writer.writeAll("...,");
        } else {
            try writer.print("{s}: ", .{fmtNameAliasingKeyword(name.string)});
            try handleType(_type.object, writer, 1 + depth);
            try writer.writeByte(',');
        }
    }

    if (params.array.items.len > 0) {
        try writer.writeByte('\n');
        try writer.writeByteNTimes(' ', depth * 4);
    }

    try writer.writeAll(") callconv(.C) ");
    try handleType(ret.object, writer, depth);
    if (proc_name != null) try writer.writeByte(';');
}

fn handleTypename(typename: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    const name = expectField(typename, "name");
    const _type = expectField(typename, "type");

    // TODO: some types can be handled better by manually defining them,
    // such as flag types (file_open_flags) or anonymous unions/structs.

    if (name.string.len == 0) {
        assert(expectKind(_type.object) == .@"enum");
        return handleUnnamedEnum(_type.object, writer, depth);
    }

    if (typename.get("doc")) |doc| {
        try handleDocComment(doc, writer, depth);
    }

    if (try Quirks.handleTypename(name.string, _type.object, writer, depth)) return;

    try writer.print("pub const {s} = ", .{fmtDeclName(name.string)});
    try handleType(_type.object, writer, depth);
    try writer.writeByte(';');
}

fn handleUnnamedEnum(_type: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    const tag_type = expectField(
        expectField(_type, "type").object,
        "kind",
    );

    const constants = expectField(_type, "constants");
    for (constants.array.items, 0..) |constant, i| {
        assert(expectKind(constant.object) == .@"enum-constant");

        const const_name = expectField(constant.object, "name");
        const const_value = expectField(constant.object, "value");

        if (i > 0) try writer.writeByteNTimes(' ', depth * 4);
        try writer.print(
            "pub const {s}: {s} = {d};",
            .{ fmtDeclName(const_name.string), tag_type.string, const_value.integer },
        );
        if (i < constants.array.items.len - 1) try writer.writeByte('\n');
    }
}

fn handleType(_type: json.ObjectMap, writer: AnyWriter, depth: u32) WriteError!void {
    const kind = expectKind(_type);
    switch (kind) {
        .array => {
            // [count]subtype

            try writer.print("[{d}]", .{expectField(_type, "count").integer});
            const subtype = expectField(_type, "type");
            try handleType(subtype.object, writer, depth);
        },
        .@"enum" => {
            // enum(type) {
            //     (enum-constant,)*
            // }

            const subtype = expectField(_type, "type");
            const tag_type = expectField(subtype.object, "kind");

            try writer.print("enum({s}) {{", .{tag_type.string});
            const constants = expectField(_type, "constants");
            if (constants.array.items.len > 0) try writer.writeByte('\n');

            for (constants.array.items) |constant| {
                assert(expectKind(constant.object) == .@"enum-constant");

                const const_name = expectField(constant.object, "name");
                const const_value = expectField(constant.object, "value");

                try writer.writeByteNTimes(' ', (1 + depth) * 4);
                if (constant.object.get("doc")) |doc| {
                    try handleDocComment(doc, writer, depth + 1);
                }
                try writer.print(
                    "{s} = {d},\n",
                    .{ fmtDeclName(const_name.string), const_value.integer },
                );
            }
            if (constants.array.items.len > 0)
                try writer.writeByteNTimes(' ', depth * 4);

            try writer.writeByte('}');
        },
        .pointer => {
            // [*c][const ]subtype
            // OR
            // ?*anyopaque

            // TODO: resolve C pointers
            // If a pointer's subtype is an opaque type, make it a ?*subtype.
            // How can we determine const-ness? i.e. [*c]const u8.
            // How can we determine nullability?

            const subtype = expectField(_type, "type");
            const subkind = expectKind(subtype.object);

            switch (subkind) {
                .void => try writer.writeAll("?*anyopaque"),
                else => {
                    try writer.writeAll("[*c]");
                    try handleType(subtype.object, writer, depth);
                },
            }
        },
        .proc => try handleProc(_type, writer, depth),
        .@"struct", .@"union" => {
            // extern struct {
            //     (struct-field,)+
            // }
            // OR
            // extern union {
            //     (union-field,)*
            // }
            // OR
            // opaque {}

            const fields = _type.get("fields") orelse {
                try writer.writeAll("opaque {}");
                return;
            };

            try writer.print("extern {s} {{\n", .{@tagName(kind)});
            var unnamed: u16 = 0;

            for (fields.array.items) |field| {
                const field_name = expectField(field.object, "name");
                const field_type = expectField(field.object, "type");

                try writer.writeByteNTimes(' ', (1 + depth) * 4);
                if (field.object.get("doc")) |doc| {
                    try handleDocComment(doc, writer, depth + 1);
                }

                if (field_name.string.len == 0) {
                    try writer.print("unnamed_{d}: ", .{unnamed});
                    unnamed += 1;
                } else {
                    // TODO: set default values to std.mem.zeroes(field_type)
                    try writer.print("{s}: ", .{fmtNameAliasingKeyword(field_name.string)});
                }
                try handleType(field_type.object, writer, 1 + depth);
                try writer.writeAll(",\n");
            }

            try writer.writeByteNTimes(' ', depth * 4);
            try writer.writeByte('}');
        },

        .bool,
        .f32,
        .f64,
        .i32,
        .i64,
        .u16,
        .u32,
        .u64,
        .u8,
        .void,
        => try writer.writeAll(@tagName(kind)),
        .char => try writer.writeAll("u8"),
        .size_t => try writer.writeAll("usize"),

        .namedType => try writer.writeAll(fmtDeclName(expectField(_type, "name").string)),

        .macro => unreachable,
        .@"variadic-param" => unreachable,
        .va_list => {
            try writer.writeAll("@compileError(\"TODO: handle va_list type\")");
            // use `std.builtin.VaList`?
        },

        else => try defaultHandler(_type, writer, depth + 1),
    }
}

fn defaultHandler(value: json.ObjectMap, writer: AnyWriter, _: u32) WriteError!void {
    const stderr = std.io.getStdErr().writer().any();

    try writer.writeAll("TODO:");
    stderr.writeAll("TODO:") catch {};
    if (value.get("kind")) |kind| {
        try writer.print(" {s}:", .{kind.string});
        stderr.print(" {s}:", .{kind.string}) catch {};
    }
    if (value.get("name")) |name| {
        try writer.print(" {s}", .{name.string});
        stderr.print(" {s}", .{name.string}) catch {};
    }

    stderr.writeByte('\n') catch {};
}

fn expectField(object: json.ObjectMap, comptime name: []const u8) json.Value {
    return object.get(name) orelse @panic("Expected '" ++ name ++ "' field");
}

fn expectKind(object: json.ObjectMap) Kind {
    // this map is generated once at compile-time
    const map: std.StaticStringMap(Kind) = comptime blk: {
        const K = @typeInfo(Kind).Enum;
        var kvs: [K.fields.len]struct { []const u8, Kind } = undefined;
        for (K.fields, 0..) |field, i| {
            kvs[i] = .{ field.name, @as(Kind, @enumFromInt(field.value)) };
        }
        break :blk std.StaticStringMap(Kind).initComptime(kvs);
    };

    const kind = expectField(object, "kind");
    return map.get(kind.string) orelse std.debug.panic("Unknown Kind type '{s}'", .{kind.string});
}

fn handleDocComment(doc: json.Value, writer: AnyWriter, depth: u32) WriteError!void {
    return switch (doc) {
        .string => |str| {
            try writer.print("/// {s}\n", .{str});
            try writer.writeByteNTimes(' ', depth * 4);
        },
        .array => |array| for (array.items) |value| {
            try writer.print("/// {s}\n", .{value.string});
            try writer.writeByteNTimes(' ', depth * 4);
        },
        else => unreachable,
    };
}

/// Intended to be used *ONCE* per print call.
fn fmtDeclName(name: []const u8) []const u8 {
    const new_name = fmtNameAliasingKeyword(stripOrcaPrefix(name));
    return new_name;
}

/// If the name aliases a Zig keyword, returns the name formatted as an identifier
/// literal backed by static memory, else returns name as is. Intended to be used
/// *ONCE* per print call.
fn fmtNameAliasingKeyword(name: []const u8) []const u8 {
    if (std.zig.Token.keywords.get(name) == null) return name;
    const Static = struct {
        var buf: [16]u8 = undefined;
    };
    return std.fmt.bufPrint(&Static.buf, "@\"{s}\"", .{name}) catch unreachable;
}

fn stripOrcaPrefix(name: []const u8) []const u8 {
    return if (name.len > 3 and (strEql(name[0..3], "oc_") or strEql(name[0..3], "OC_")))
        name[3..]
    else
        name;
}

/// Intended to be used inside main
fn fatal(comptime fmt: []const u8, args: anytype) u8 {
    std.log.err(fmt, args);
    return 1;
}

fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Handle oddities and idiosyncrasies in the api definitions.
/// Code here is intentionally brittle to changes in api.json.
const Quirks = struct {
    fn handleModule(name: []const u8, writer: AnyWriter) WriteError!void {
        // These types aren't yet included in the api.json,
        // not sure why. -jdelsi Jan 8, 2025
        if (strEql(name, "Application")) {
            // oc_window
            try writer.writeAll("pub const window = u64;\n");
        } else if (strEql(name, "Memory")) {
            // oc_pool
            try writer.writeAll(
                \\pub const pool = extern struct {
                \\    arena: arena,
                \\    freeList: list,
                \\    blockSize: u64,
                \\};
                \\
            );
        }
    }

    /// Returns true if the typename should be skipped.
    fn handleTypename(
        name: []const u8,
        _type: json.ObjectMap,
        writer: AnyWriter,
        depth: u32,
    ) WriteError!bool {
        if (std.mem.startsWith(u8, name, "oc_vec")) {
            assert(expectKind(_type) == .@"union");
            const vec_struct = expectField(_type, "fields").array.items[0].object;
            assert(strEql(expectField(vec_struct, "name").string, ""));

            const vec_type = expectField(vec_struct, "type").object;
            assert(expectKind(vec_type) == .@"struct");

            try writer.print("pub const {s} = ", .{fmtDeclName(name)});
            try handleType(vec_type, writer, depth);
            try writer.writeByte(';');

            return true;
        }

        if (strEql(name, "oc_rect")) {
            assert(expectKind(_type) == .@"union");
            const xywh_fields = expectField(_type, "fields").array.items[0].object;
            const subtype = expectField(xywh_fields, "type").object;
            assert(expectKind(subtype) == .@"struct");

            try writer.print("pub const {s} = ", .{fmtDeclName(name)});
            try handleType(subtype, writer, depth);
            try writer.writeByte(';');

            return true;
        }

        if (strEql(name, "oc_ui_box")) {
            assert(expectKind(_type) == .@"struct");
            return _type.get("fields") == null;
        }

        if (strEql(name, "oc_color")) {
            assert(expectKind(_type) == .@"struct");
            const color_fields = expectField(_type, "fields").array;

            const rgba_union = expectField(color_fields.items[0].object, "type").object;
            assert(expectKind(rgba_union) == .@"union");

            const rgba_union_fields = expectField(rgba_union, "fields").array;
            const rgba_struct = expectField(rgba_union_fields.items[0].object, "type").object;
            assert(expectKind(rgba_struct) == .@"struct");

            const rgba_struct_fields = expectField(rgba_struct, "fields").array;

            const color_space = color_fields.items[1].object;
            assert(strEql(expectField(color_space, "name").string, "colorSpace"));

            var combined_fields: [5]json.ObjectMap = undefined;
            for (combined_fields[0..4], rgba_struct_fields.items[0..4]) |*dst, src| dst.* = src.object;
            combined_fields[4] = color_space;

            try writer.print("pub const {s} = extern struct {{\n", .{fmtDeclName(name)});

            // @Cleanup duplicated code
            for (combined_fields) |field| {
                const field_name = expectField(field, "name");
                const field_type = expectField(field, "type");

                try writer.writeByteNTimes(' ', (1 + depth) * 4);
                if (field.get("doc")) |doc| {
                    try handleDocComment(doc, writer, depth + 1);
                }

                assert(field_name.string.len > 0);
                try writer.print("{s}: ", .{fmtNameAliasingKeyword(field_name.string)});
                try handleType(field_type.object, writer, 1 + depth);
                try writer.writeAll(",\n");
            }

            try writer.writeByteNTimes(' ', depth * 4);
            try writer.writeAll("};");

            return true;
        }

        return false;
    }
};
