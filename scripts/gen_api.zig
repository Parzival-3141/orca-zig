//! This script will generate the Zig bindings for the Orca api using an api.json file.

const std = @import("std");
const json = std.json;
const assert = std.debug.assert;

// api.json wishlist:
// - format documentation
// - format and api versioning!!!
// - specify pointer types (single/multi-item, nullable, mutable, etc...)
// - change module brief to doc for consistency
// - remove unnamed enums, create a dedicated "constant" kind instead
// - make OC_UI_STYLE a proper enum
// - oc_pool and oc_window are missing typename entries
// - flag enum types should be differentiated from normal enums
// - flag enum types should use the correct backing values (i.e. oc_file_open_flags_enum should use u16 not u32)

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

    var diag: std.json.Diagnostics = .{};
    var scanner = std.json.Scanner.initCompleteInput(allocator, api_src);
    scanner.enableDiagnostics(&diag);

    const api = std.json.parseFromTokenSourceLeaky(std.json.Value, allocator, &scanner, .{}) catch |err| {
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

    // TODO: parse json tokens directly instead of parsing nested Value types
    for (api.array.items) |module| {
        assert(expectKind(module.object) == .module);
        try handleModule(module.object, writer.any(), 0);
    }

    try bw.flush();

    return 0;
}

const WriteError = anyerror;

fn handleModule(module: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
    const name = expectField(module, "name");
    const brief = expectField(module, "brief");

    try writer.print(
        \\// ==== {s} ====
        \\// {s}
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
fn handleModuleNamespaced(module: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
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

fn handleMacro(macro: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
    if (macro.get("doc")) |doc| {
        try handleDocComment(doc, writer, depth);
    }
    const name = expectField(macro, "name");
    try writer.print(
        "pub const {s} = @compileError(\"TODO: translate macro\");",
        .{name.string},
    );
}

fn handleProc(proc: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
    // [doc-comment]
    // (pub extern)|*const fn [name](([doc-comment] param: type,)*) callconv(.C) type;

    const ret = expectField(proc, "return");
    const params = expectField(proc, "params");

    const proc_name = proc.get("name");
    if (proc_name) |name| {
        if (proc.get("doc")) |doc| {
            try handleDocComment(doc, writer, depth);
        }
        try writer.print("pub extern fn {s}(", .{name.string});
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
            try writer.print("{s}: ", .{name.string});
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

fn handleTypename(typename: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
    const name = expectField(typename, "name");
    const _type = expectField(typename, "type");

    // TODO: some types can be handled better by manually defining them,
    // such as the vector types. E.g. pub const oc_vec2 = [2]f32;

    if (name.string.len == 0) {
        assert(expectKind(_type.object) == .@"enum");
        return handleUnnamedEnum(_type.object, writer, depth);
    }

    if (typename.get("doc")) |doc| {
        try handleDocComment(doc, writer, depth);
    }

    if (try Quirks.handleTypename(name.string, _type.object, writer, depth)) return;

    try writer.print("pub const {s} = ", .{name.string});
    try handleType(_type.object, writer, depth);
    try writer.writeByte(';');
}

fn handleUnnamedEnum(_type: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
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
            .{ const_name.string, tag_type.string, const_value.integer },
        );
        if (i < constants.array.items.len - 1) try writer.writeByte('\n');
    }
}

fn handleType(_type: json.ObjectMap, writer: std.io.AnyWriter, depth: u32) WriteError!void {
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
                    .{ const_name.string, const_value.integer },
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
            // If a pointer's subtype is a u8, make it a [*c]const u8.
            // If a pointer's subtype is an opaque type, make it a ?*subtype.

            const subtype = expectField(_type, "type");
            try writer.writeAll("[*c]");
            try handleType(subtype.object, writer, depth);
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
                    // Using identifier literals here to handle fields that alias keywords (error, align, etc.)
                    // Redundant cases will be removed when the builder runs the output through 'zig fmt'.
                    try writer.print("@\"{s}\": ", .{field_name.string});
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
        .namedType => try writer.writeAll(expectField(_type, "name").string),

        .macro => unreachable,
        .@"variadic-param" => unreachable,
        .va_list => {
            try writer.writeAll("@compileError(\"TODO: handle va_list type\")");
            // use `std.builtin.VaList`?
        },

        else => try defaultHandler(_type, writer, depth + 1),
    }
}

fn defaultHandler(value: json.ObjectMap, writer: std.io.AnyWriter, _: u32) WriteError!void {
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
    const kind = expectField(object, "kind");

    const map: std.StaticStringMap(Kind) = comptime blk: {
        const K = @typeInfo(Kind);
        var kvs: [K.Enum.fields.len]struct { []const u8, Kind } = undefined;
        for (K.Enum.fields, 0..) |field, i| {
            kvs[i] = .{ field.name, @as(Kind, @enumFromInt(field.value)) };
        }
        break :blk std.StaticStringMap(Kind).initComptime(kvs);
    };

    return map.get(kind.string) orelse std.debug.panic("Unknown Kind type '{s}'", .{kind.string});
}

fn handleDocComment(doc: json.Value, writer: std.io.AnyWriter, depth: u32) WriteError!void {
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

/// Intended to be used inside main
fn fatal(comptime fmt: []const u8, args: anytype) u8 {
    std.log.err(fmt, args);
    return 1;
}

fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Code here is intentionally brittle to changes in api.json.
const Quirks = struct {
    fn handleModule(name: []const u8, writer: std.io.AnyWriter) WriteError!void {
        // These types aren't yet included in the api.json,
        // not sure why. -jdelsi Jan 8, 2025
        if (strEql(name, "Application")) {
            try writer.writeAll("pub const oc_window = u64;\n");
        } else if (strEql(name, "Memory")) {
            try writer.writeAll(
                \\pub const oc_pool = extern struct {
                \\    arena: oc_arena,
                \\    freeList: oc_list,
                \\    blockSize: u64,
                \\};
                \\
            );
        }
    }

    fn handleTypename(
        name: []const u8,
        _type: json.ObjectMap,
        writer: std.io.AnyWriter,
        depth: u32,
    ) WriteError!bool {
        if (std.mem.startsWith(u8, name, "oc_vec")) {
            assert(expectKind(_type) == .@"union");
            const vec_array = expectField(_type, "fields").array.items[1].object;
            assert(strEql(expectField(vec_array, "name").string, "c"));

            try writer.print("pub const {s} = ", .{name});
            try handleType(expectField(vec_array, "type").object, writer, depth);
            try writer.writeByte(';');

            return true;
        }

        if (strEql(name, "oc_mat2x3")) {
            assert(expectKind(_type) == .@"struct");
            const m = expectField(_type, "fields").array.items[0].object;
            assert(strEql(expectField(m, "name").string, "m"));

            try writer.writeAll("///\n");
            try writer.writeByteNTimes(' ', depth * 4);
            try writer.writeAll("/// The elements of the matrix are stored in row-major order.\n");
            try writer.writeByteNTimes(' ', depth * 4);

            try writer.print("pub const {s} = ", .{name});
            try handleType(expectField(m, "type").object, writer, depth);
            try writer.writeByte(';');

            return true;
        }

        if (strEql(name, "oc_rect")) {
            assert(expectKind(_type) == .@"union");
            const xy_wh = expectField(_type, "fields").array.items[1].object;
            const subtype = expectField(xy_wh, "type").object;
            assert(expectKind(subtype) == .@"struct");

            try writer.print("pub const {s} = ", .{name});
            try handleType(subtype, writer, depth);
            try writer.writeByte(';');

            return true;
        }

        return false;
    }
};
