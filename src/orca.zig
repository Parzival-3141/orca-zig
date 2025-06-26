const std = @import("std");

// @Cleanup convert @Api tags into issues in the orca repository
// @Incomplete add doc comments for return values

pub const panic = std.debug.FullPanic(panicImpl);
fn panicImpl(msg: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);
    _ = first_trace_addr; // @Incomplete: stack trace
    debug.abort("panic: {s}", .{msg}, @src());
}

// shortcuts
pub const log = debug.log;
pub const assert = debug.assert;
pub const abort = debug.abort;

/// **WARNING** Erases const type info! This function only accepts const
/// pointers to avoid excessive casting when passing string literals.
/// Be careful when passing the result to API's which may modify the buffer.
pub fn toStr8(buf: []const u8) strings.Str8 {
    return strings.Str8.fromSlice(@constCast(buf));
}

//------------------------------------------------------------------------------------------
// [Utility] Utility data structures and helpers used throughout the Orca API.
//------------------------------------------------------------------------------------------

pub const math = @import("math.zig"); // [Algebra]
pub const debug = @import("debug.zig"); // [Debug]
pub const mem = @import("mem.zig"); // [Memory]
pub const List = @import("list.zig").List; // [Lists]
pub const strings = @import("strings.zig"); // [Strings]
pub const utf8 = @import("utf8.zig"); // [UTF8]

pub const app = @import("app.zig"); // [Application]
pub const io = @import("io.zig"); // [I/O]
pub const graphics = @import("graphics.zig"); // [Graphics]
pub const ui = @import("ui.zig"); // [UI]

// @Api missing clock stuff
pub const clock = struct {
    const Kind = enum(c_int) {
        /// clock that increment monotonically
        monotonic,
        /// clock that increment monotonically during uptime
        uptime,
        /// clock that is driven by the platform time
        date,
    };

    pub const time = oc_clock_time;
    extern fn oc_clock_time(clock: Kind) f64;
};

//------------------------------------------------------------------------------------------
// [Orca hooks]
//------------------------------------------------------------------------------------------

const user_root = @import("user_root");

// TODO: document callbacks
comptime {
    maybeExportCallback("onInit", "oc_on_init");
    maybeExportCallback("onMouseDown", "oc_on_mouse_down");
    maybeExportCallback("onMouseUp", "oc_on_mouse_up");
    maybeExportCallback("onMouseEnter", "oc_on_mouse_enter");
    maybeExportCallback("onMouseLeave", "oc_on_mouse_leave");
    maybeExportCallback("onMouseMove", "oc_on_mouse_move");
    maybeExportCallback("onMouseWheel", "oc_on_mouse_wheel");
    maybeExportCallback("onKeyDown", "oc_on_key_down");
    maybeExportCallback("onKeyUp", "oc_on_key_up");
    maybeExportCallback("onFrameRefresh", "oc_on_frame_refresh");
    maybeExportCallback("onResize", "oc_on_resize");
    maybeExportCallback("onRawEvent", "oc_on_raw_event");
    maybeExportCallback("onTerminate", "oc_on_terminate");
}

fn maybeExportCallback(comptime handler: []const u8, comptime callback: []const u8) void {
    if (@hasDecl(user_root, handler)) {
        const func = &@field(@This(), callback);
        @export(func, .{ .name = callback });
    }
}

fn oc_on_init() callconv(.C) void {
    callHandler(user_root.onInit, .{}, @src());
}

fn oc_on_mouse_down(button: app.MouseButton) callconv(.C) void {
    callHandler(user_root.onMouseDown, .{button}, @src());
}

fn oc_on_mouse_up(button: app.MouseButton) callconv(.C) void {
    callHandler(user_root.onMouseUp, .{button}, @src());
}

fn oc_on_mouse_enter() callconv(.C) void {
    callHandler(user_root.onMouseEnter, .{}, @src());
}

fn oc_on_mouse_leave() callconv(.C) void {
    callHandler(user_root.onMouseLeave, .{}, @src());
}

fn oc_on_mouse_move(x: f32, y: f32, deltaX: f32, deltaY: f32) callconv(.C) void {
    callHandler(user_root.onMouseMove, .{ x, y, deltaX, deltaY }, @src());
}

fn oc_on_mouse_wheel(deltaX: f32, deltaY: f32) callconv(.C) void {
    callHandler(user_root.onMouseWheel, .{ deltaX, deltaY }, @src());
}

fn oc_on_key_down(scan: app.ScanCode, key: app.KeyCode) callconv(.C) void {
    callHandler(user_root.onKeyDown, .{ scan, key }, @src());
}

fn oc_on_key_up(scan: app.ScanCode, key: app.KeyCode) callconv(.C) void {
    callHandler(user_root.onKeyUp, .{ scan, key }, @src());
}

fn oc_on_frame_refresh() callconv(.C) void {
    callHandler(user_root.onFrameRefresh, .{}, @src());
}

fn oc_on_resize(width: u32, height: u32) callconv(.C) void {
    callHandler(user_root.onResize, .{ width, height }, @src());
}

fn oc_on_raw_event(c_event: *app.Event) callconv(.C) void {
    callHandler(user_root.onRawEvent, .{c_event}, @src());
}

fn oc_on_terminate() callconv(.C) void {
    callHandler(user_root.onTerminate, .{}, @src());
}

fn callHandler(func: anytype, params: anytype, source: std.builtin.SourceLocation) void {
    const bad_return_type = "Orca event handlers must have a return type of 'void' or '!void'";
    const ReturnType = @typeInfo(@typeInfo(@TypeOf(func)).@"fn".return_type.?);

    const CustomStackTrace = struct {
        inner: *std.builtin.StackTrace,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            if (fmt.len != 0) std.fmt.invalidFmtError(fmt, self);
            _ = options;

            // const debug_info = std.debug.getSelfDebugInfo() catch |err| {
            //     return writer.print("\nUnable to print stack trace: Unable to open debug info: {s}\n", .{@errorName(err)});
            // };

            // std.debug.StackIterator.init().next()

            // try writer.writeAll("\n");
            // std.debug.writeStackTrace(self.inner.*, writer, debug_info, .no_color) catch |err| {
            //     try writer.print("Unable to print stack trace: {s}\n", .{@errorName(err)});
            // };

            const stack_trace = self.inner;

            // writeStackTrace()
            if (@import("builtin").strip_debug_info) return;
            var frame_index: usize = 0;
            var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

            while (frames_left != 0) : ({
                frames_left -= 1;
                frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
            }) {
                const return_address = stack_trace.instruction_addresses[frame_index];
                try printUnknownSource(writer, return_address - 1);
            }

            if (stack_trace.index > stack_trace.instruction_addresses.len) {
                const dropped_frames = stack_trace.index - stack_trace.instruction_addresses.len;
                try writer.print("({d} additional stack frames skipped...)\n", .{dropped_frames});
            }
        }

        fn printUnknownSource(out_stream: anytype, address: usize) !void {
            return printLineInfo(
                out_stream,
                address,
                "???",
                "???",
            );
        }

        fn printLineInfo(
            out_stream: anytype,
            address: usize,
            symbol_name: []const u8,
            compile_unit_name: []const u8,
        ) !void {
            try out_stream.writeAll("???:?:?");
            try out_stream.writeAll(": ");
            try out_stream.print(
                "0x{x} in {s} ({s})",
                .{ address, symbol_name, compile_unit_name },
            );
            try out_stream.writeAll("\n");
        }
    };

    switch (ReturnType) {
        .void => @call(.auto, func, params),
        .error_union => |eu| {
            if (eu.payload != void) @compileError(bad_return_type);

            @call(.auto, func, params) catch |err| {
                @branchHint(.unlikely);
                // @Incomplete error return trace

                // var buf: [1024]u8 = undefined;
                // var fba = std.heap.FixedBufferAllocator.init(&buf);

                // const builtin = @import("builtin");

                // var dwf: std.debug.Dwarf = .{
                //     .is_macho = false,
                //     .endian = builtin.cpu.arch.endian(),
                // };
                // dwf.open(fba.allocator()) catch @panic("uh oh");

                // std.debug.StackIterator.init(first_address: ?usize, fp: ?usize)

                // debug.log.err("{s}", .{@errorName(err)}, source);
                // if (@errorReturnTrace()) |trace| {
                //     std.debug.dumpStackTrace(trace.*);
                // }
                if (@errorReturnTrace()) |trace| {
                    debug.abort(
                        "Caught error: {}\n{}",
                        .{ err, CustomStackTrace{ .inner = trace } },
                        source,
                    );
                } else {
                    debug.abort("Caught error: {}", .{err}, source);
                }
            };
        },
        else => @compileError(bad_return_type),
    }
}
