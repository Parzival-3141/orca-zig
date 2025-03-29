const std = @import("std");
const oc = @import("root");

var frame_size: oc.vec2 = .{ .x = 1200, .y = 838 };

var surface: oc.surface = undefined;
var renderer: oc.canvas_renderer = undefined;
var canvas: oc.canvas_context = undefined;

var font_regular: oc.font = undefined;
var font_bold: oc.font = undefined;

var ui: *oc.ui_context = undefined;

var text_arena: oc.arena = undefined;
var log_arena: oc.arena = undefined;
var log_lines: oc.str8_list = undefined;

var theme: enum { dark, light } = .dark;

pub fn onInit() !void {
    oc.window_set_title(oc.to_str8(@constCast("Orca Zig UI Demo")));
    oc.window_set_size(frame_size);

    renderer = oc.canvas_renderer_create();
    surface = oc.canvas_surface_create(renderer);
    canvas = oc.canvas_context_create();

    const fonts = [_]*oc.font{ &font_regular, &font_bold };
    const font_names = [_][]const u8{ "/OpenSans-Regular.ttf", "/OpenSans-Bold.ttf" };
    for (fonts, font_names) |font, name| {
        const scratch = oc.scratch_begin();
        defer oc.arena_scope_end(scratch);

        const file = oc.file_open(
            oc.to_str8(@constCast(name)),
            @intFromEnum(oc.file_access_enum.FILE_ACCESS_READ),
            0,
        );
        if (oc.file_last_error(file) != @intFromEnum(oc.io_error_enum.IO_OK)) {
            oc.log.err("Couldn't open file {s}", .{name}, @src());
            return;
        }

        const size = oc.file_size(file);
        const buffer: [*]u8 = @ptrCast(oc.arena_push(scratch.arena, size));
        _ = oc.file_read(file, size, buffer);
        oc.file_close(file);

        var ranges = [5]oc.unicode_range{
            .{ .firstCodePoint = 0x0000, .count = 127 }, // BASIC_LATIN
            .{ .firstCodePoint = 0x0080, .count = 127 }, // C1_CONTROLS_AND_LATIN_1_SUPPLEMENT
            .{ .firstCodePoint = 0x0100, .count = 127 }, // LATIN_EXTENDED_A
            .{ .firstCodePoint = 0x0180, .count = 207 }, // LATIN_EXTENDED_B
            .{ .firstCodePoint = 0xfff0, .count = 15 }, //  SPECIALS
        };

        font.* = oc.font_create_from_memory(
            oc.str8_from_buffer(size, buffer),
            @intCast(ranges.len),
            &ranges,
        );
    }

    ui = oc.ui_context_create(font_regular).?;

    oc.arena_init(&text_arena);
    oc.arena_init(&log_arena);
    oc.list_init(&log_lines.list);
}

pub fn onRawEvent(event: *oc.event) void {
    oc.ui_process_event(event);
}

pub fn onResize(width: u32, height: u32) void {
    frame_size.x = @floatFromInt(width);
    frame_size.y = @floatFromInt(height);
}

pub fn onFrameRefresh() !void {
    const scratch = oc.scratch_begin();
    defer oc.arena_scope_end(scratch);

    {
        oc.ui_frame_begin(frame_size);
        defer oc.ui_frame_end();

        switch (theme) {
            .dark => oc.ui_theme_dark(),
            .light => oc.ui_theme_light(),
        }

        oc.ui_style_set_var_str8(.UI_BG_COLOR, oc.to_str8(@constCast("bg-0")));
        oc.ui_style_set_i32(.UI_CONSTRAIN_Y, 1);

        //--------------------------------------------------------------------------------------------
        // Menu bar
        //--------------------------------------------------------------------------------------------
        {
            oc.ui_menu_bar_begin(@constCast("menu_bar"));
            defer oc.ui_menu_bar_end();

            {
                oc.ui_menu_begin(@constCast("file-menu"), @constCast("File"));
                defer oc.ui_menu_end();

                if (oc.ui_menu_button(@constCast("quit"), @constCast("Quit")).pressed) {
                    oc.request_quit();
                }
            }

            {
                oc.ui_menu_begin(@constCast("theme-menu"), @constCast("Theme"));
                defer oc.ui_menu_end();

                if (oc.ui_menu_button(@constCast("dark"), @constCast("Dark theme")).pressed) {
                    theme = .dark;
                }
                if (oc.ui_menu_button(@constCast("light"), @constCast("Light theme")).pressed) {
                    theme = .light;
                }
            }
        }

        {
            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("main panel")));
            defer _ = oc.ui_box_end();

            oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
            oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1, .relax = 1 }));

            {
                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("background")));
                defer _ = oc.ui_box_end();

                oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
                oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1, .relax = 1 }));
                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_X));
                oc.ui_style_set_f32(.UI_MARGIN_X, 16);
                oc.ui_style_set_f32(.UI_MARGIN_Y, 16);
                oc.ui_style_set_f32(.UI_SPACING, 16);

                {
                    column_begin("widgets", 1.0 / 3.0);
                    defer column_end();

                    {
                        _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("top")));
                        defer _ = oc.ui_box_end();

                        oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
                        oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_X));
                        oc.ui_style_set_f32(.UI_SPACING, 32);

                        {
                            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("top_left")));
                            defer _ = oc.ui_box_end();

                            oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                            oc.ui_style_set_f32(.UI_SPACING, 24);

                            //-----------------------------------------------------------------------------
                            // Label
                            //-----------------------------------------------------------------------------
                            _ = oc.ui_label(@constCast("label"), @constCast("Label"));

                            //-----------------------------------------------------------------------------
                            // Button
                            //-----------------------------------------------------------------------------
                            if (oc.ui_button(@constCast("button"), @constCast("Button")).clicked) {
                                log_push("Button clicked");
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("checkbox")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_X));
                                oc.ui_style_set_i32(.UI_ALIGN_Y, @intFromEnum(oc.ui_align.UI_ALIGN_CENTER));
                                oc.ui_style_set_f32(.UI_SPACING, 8);
                                oc.ui_style_set_f32(.UI_MARGIN_X, 2);

                                //-------------------------------------------------------------------------
                                // Checkbox
                                //-------------------------------------------------------------------------
                                const S = struct {
                                    var checked: bool = false;
                                };
                                if (oc.ui_checkbox(@constCast("checkbox"), &S.checked).clicked) {
                                    if (S.checked) {
                                        log_push("Checkbox checked");
                                    } else {
                                        log_push("Checkbox unchecked");
                                    }
                                }

                                _ = oc.ui_label(@constCast("label"), @constCast("Checkbox"));
                            }
                        }

                        //---------------------------------------------------------------------------------
                        // Vertical slider
                        //---------------------------------------------------------------------------------
                        const vSlider = struct {
                            var value: f32 = 0;
                            var logged_value: f32 = 0;
                            var log_time: f64 = 0;
                        };

                        {
                            oc.ui_style_rule_begin(oc.to_str8(@constCast("v_slider")));
                            defer oc.ui_style_rule_end();

                            oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 24 }));
                            oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 130 }));
                        }

                        _ = oc.ui_slider(@constCast("v_slider"), &vSlider.value);

                        // TODO missing oc.clock_time
                        // const now = oc.clock_time(.CLOCK_MONOTONIC);
                        // if((now - vSlider.log_time) >= 0.2 and vSlider.value != vSlider.logged_value)
                        // {
                        //     log_pushf("Vertical slider moved to %f", vSlider.value);
                        //     vSlider.logged_value = vSlider.value;
                        //     vSlider.log_time = now;
                        // }

                        {
                            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("top_right")));
                            defer _ = oc.ui_box_end();

                            oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                            oc.ui_style_set_f32(.UI_SPACING, 24);

                            //-----------------------------------------------------------------------------
                            // Tooltip
                            //-----------------------------------------------------------------------------
                            if (oc.ui_label(@constCast("label"), @constCast("Tooltip")).hover) {
                                oc.ui_tooltip(@constCast("tooltip"), @constCast("Hi"));
                            }

                            //-----------------------------------------------------------------------------
                            // Radio group
                            //-----------------------------------------------------------------------------

                            const Radio = struct {
                                var selected: i32 = 0;
                            };
                            const options = [_]oc.str8{
                                oc.to_str8(@constCast("Radio 1")),
                                oc.to_str8(@constCast("Radio 2")),
                            };
                            var radioGroupInfo: oc.ui_radio_group_info = .{
                                .changed = false,
                                .selectedIndex = Radio.selected,
                                .optionCount = options.len,
                                .options = @constCast(&options),
                            };
                            const result = oc.ui_radio_group(@constCast("radio_group"), &radioGroupInfo);
                            Radio.selected = result.selectedIndex;
                            if (result.changed) {
                                log_pushf("Selected {s}", .{options[@intCast(result.selectedIndex)].ptr});
                            }

                            //-----------------------------------------------------------------------------
                            // Horizontal slider
                            //-----------------------------------------------------------------------------

                            const hSlider = struct {
                                var value: f32 = 0;
                                var logged_value: f32 = 0;
                                var log_time: f64 = 0;
                            };

                            {
                                oc.ui_style_rule_begin(oc.to_str8(@constCast("h_slider")));
                                defer oc.ui_style_rule_end();

                                oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 130 }));
                                oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 24 }));
                            }

                            _ = oc.ui_slider(@constCast("h_slider"), &hSlider.value);

                            // TODO missing oc.clock_time
                            // const now = oc.clock_time(.CLOCK_MONOTONIC);
                            // if((now - hSlider.log_time) >= 0.2 and hSlider.value != hSlider.logged_value)
                            // {
                            //     log_pushf("hSlider moved to %f", hSlider.value);
                            //     hSlider.logged_value = hSlider.value;
                            //     hSlider.log_time = now;
                            // }
                        }
                    }

                    //-------------------------------------------------------------------------------------
                    // Text box
                    //-------------------------------------------------------------------------------------
                    {
                        {
                            oc.ui_style_rule_begin(oc.to_str8(@constCast("text")));
                            defer oc.ui_style_rule_end();

                            oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 305 }));
                        }

                        const S = struct {
                            var text_info: oc.ui_text_box_info = std.mem.zeroInit(oc.ui_text_box_info, .{
                                .defaultText = oc.to_str8(@constCast("Type here")),
                            });
                        };
                        const result = oc.ui_text_box(@constCast("text"), scratch.arena, &S.text_info);
                        if (result.changed) {
                            oc.arena_clear(&text_arena);
                            S.text_info.text = oc.str8_push_copy(&text_arena, result.text);
                        }
                        if (result.accepted) {
                            log_pushf("Entered text \"{s}\"", .{S.text_info.text.ptr});
                        }
                    }

                    //-------------------------------------------------------------------------------------
                    // Select
                    //-------------------------------------------------------------------------------------
                    {
                        const S = struct {
                            var selected: i32 = -1;
                        };
                        const options = [_]oc.str8{
                            oc.to_str8(@constCast("Option 1")),
                            oc.to_str8(@constCast("Option 2")),
                        };

                        var info: oc.ui_select_popup_info = .{
                            .changed = false,
                            .selectedIndex = S.selected,
                            .optionCount = 2,
                            .options = @constCast(&options),
                            .placeholder = oc.to_str8(@constCast("Select")),
                        };
                        const result = oc.ui_select_popup(@constCast("select"), &info);
                        if (result.selectedIndex != S.selected) {
                            log_pushf("Selected {s}", .{options[@intCast(result.selectedIndex)].ptr});
                        }
                        S.selected = result.selectedIndex;
                    }

                    //-------------------------------------------------------------------------------------
                    // Scrollable panel
                    //-------------------------------------------------------------------------------------
                    {
                        _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("log")));
                        defer _ = oc.ui_box_end();

                        oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
                        oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1, .relax = 1, .minSize = 200 }));
                        oc.ui_style_set_var_str8(.UI_BG_COLOR, oc.to_str8(@constCast("bg-2")));
                        oc.ui_style_set_var_str8(.UI_BORDER_COLOR, oc.to_str8(@constCast("border")));
                        oc.ui_style_set_f32(.UI_BORDER_SIZE, 1);
                        oc.ui_style_set_var_str8(.UI_ROUNDNESS, oc.to_str8(@constCast("roundness-small")));

                        oc.ui_style_set_i32(.UI_OVERFLOW_Y, @intFromEnum(oc.ui_overflow.UI_OVERFLOW_SCROLL));

                        {
                            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("contents")));
                            defer _ = oc.ui_box_end();

                            oc.ui_style_set_f32(.UI_MARGIN_X, 16);
                            oc.ui_style_set_f32(.UI_MARGIN_Y, 16);
                            oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));

                            if (oc.list_empty(log_lines.list)) {
                                {
                                    oc.ui_style_rule_begin(oc.to_str8(@constCast("label")));
                                    defer oc.ui_style_rule_end();

                                    oc.ui_style_set_var_str8(.UI_COLOR, oc.to_str8(@constCast("text-2")));
                                }
                                _ = oc.ui_label(@constCast("label"), @constCast("Log"));
                            }

                            var i: usize = 0;
                            var log_line: ?*oc.str8_elt = oc_list_checked_entry(log_lines.list.first, oc.str8_elt, "listElt");
                            while (log_line) |line| : ({
                                i += 1;
                                log_line = oc_list_checked_entry(line.listElt.next, oc.str8_elt, "listElt");
                            }) {
                                var buf: [15]u8 = undefined;
                                const id = try std.fmt.bufPrint(&buf, "{d}", .{i});
                                _ = oc.ui_label_str8(oc.to_str8(id), line.string);
                            }
                        }
                    }
                }

                //-----------------------------------------------------------------------------------------
                // Styling
                //-----------------------------------------------------------------------------------------
                {
                    column_begin("styling", 2.0 / 3.0);
                    defer column_end();

                    const Unselected = struct {
                        var width: f32 = 16;
                        var height: f32 = 16;
                        var roundness: f32 = 8;
                        var bgColor: oc.color = .{
                            .r = 0,
                            .g = 0,
                            .b = 0,
                            .a = 0,
                            .colorSpace = .COLOR_SPACE_RGB,
                        };
                        var borderColor: oc.color = .{
                            .r = 0.976,
                            .g = 0.976,
                            .b = 0.976,
                            .a = 0.35,
                            .colorSpace = .COLOR_SPACE_RGB,
                        };
                        var borderSize: f32 = 1;
                        var whenStatus = oc.to_str8(@constCast(""));
                    };

                    const Selected = struct {
                        var width: f32 = 16;
                        var height: f32 = 16;
                        var roundness: f32 = 8;
                        var centerColor: oc.color = .{
                            .r = 1,
                            .g = 1,
                            .b = 1,
                            .a = 1,
                            .colorSpace = .COLOR_SPACE_RGB,
                        };
                        var bgColor: oc.color = .{
                            .r = 0.33,
                            .g = 0.66,
                            .b = 1,
                            .a = 1,
                            .colorSpace = .COLOR_SPACE_RGB,
                        };
                        var borderSize: f32 = 1;
                        var whenStatus = oc.to_str8(@constCast(""));
                        var index: i32 = 0;
                    };

                    const Label = struct {
                        var fontColor: oc.color = .{ .r = 0.976, .g = 0.976, .b = 0.976, .a = 1, .colorSpace = .COLOR_SPACE_RGB };
                        var font: *oc.font = &font_regular;
                        var fontSize: f32 = 14;
                    };

                    {
                        _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("styled_radios")));
                        defer _ = oc.ui_box_end();

                        oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
                        oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 152 }));
                        oc.ui_style_set_color(.UI_BG_COLOR, .{ .r = 0.086, .g = 0.086, .b = 0.102, .a = 1, .colorSpace = .COLOR_SPACE_RGB });
                        oc.ui_style_set_var_str8(.UI_ROUNDNESS, oc.to_str8(@constCast("roundness-small")));

                        oc.ui_style_set_i32(.UI_ALIGN_X, @intFromEnum(oc.ui_align.UI_ALIGN_CENTER));
                        oc.ui_style_set_i32(.UI_ALIGN_Y, @intFromEnum(oc.ui_align.UI_ALIGN_CENTER));

                        {
                            var list: oc.str8_list = std.mem.zeroes(oc.str8_list);
                            oc.str8_list_push(scratch.arena, &list, oc.to_str8(@constCast("radio_group .radio-row")));
                            oc.str8_list_push(scratch.arena, &list, Unselected.whenStatus);
                            oc.str8_list_push(scratch.arena, &list, oc.to_str8(@constCast(" .radio")));
                            const unselected_pattern = oc.str8_list_join(scratch.arena, list);

                            {
                                oc.ui_style_rule_begin(unselected_pattern);
                                defer oc.ui_style_rule_end();

                                oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = Unselected.width }));
                                oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = Unselected.height }));
                                oc.ui_style_set_color(.UI_BG_COLOR, Unselected.bgColor);
                                oc.ui_style_set_color(.UI_BORDER_COLOR, Unselected.borderColor);
                                oc.ui_style_set_f32(.UI_BORDER_SIZE, Unselected.borderSize);
                                oc.ui_style_set_f32(.UI_ROUNDNESS, Unselected.roundness);
                            }
                        }

                        {
                            var list: oc.str8_list = std.mem.zeroes(oc.str8_list);
                            oc.str8_list_push(scratch.arena, &list, oc.to_str8(@constCast("radio_group .radio-row")));
                            oc.str8_list_push(scratch.arena, &list, Selected.whenStatus);
                            oc.str8_list_push(scratch.arena, &list, oc.to_str8(@constCast(" .radio_selected")));
                            const selected_pattern = oc.str8_list_join(scratch.arena, list);

                            {
                                oc.ui_style_rule_begin(selected_pattern);
                                defer oc.ui_style_rule_end();

                                oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = Selected.width }));
                                oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = Selected.height }));
                                oc.ui_style_set_color(.UI_BG_COLOR, Selected.bgColor);
                                oc.ui_style_set_color(.UI_COLOR, Selected.centerColor);
                                oc.ui_style_set_f32(.UI_ROUNDNESS, Selected.roundness);
                            }
                        }

                        {
                            oc.ui_style_rule_begin(oc.to_str8(@constCast("radio_group label")));
                            defer oc.ui_style_rule_end();

                            oc.ui_style_set_color(.UI_COLOR, Label.fontColor);
                            oc.ui_style_set_font(.UI_FONT, Label.font.*);
                            oc.ui_style_set_f32(.UI_TEXT_SIZE, Label.fontSize);
                        }

                        const options = [_]oc.str8{
                            oc.to_str8(@constCast("I")),
                            oc.to_str8(@constCast("Am")),
                            oc.to_str8(@constCast("Stylish")),
                        };
                        var radioGroupInfo: oc.ui_radio_group_info = .{
                            .changed = false,
                            .selectedIndex = Selected.index,
                            .optionCount = options.len,
                            .options = @constCast(&options),
                        };
                        const result = oc.ui_radio_group(@constCast("radio_group"), &radioGroupInfo);
                        Selected.index = result.selectedIndex;
                    }

                    {
                        _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("controls")));
                        defer _ = oc.ui_box_end();

                        oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_X));
                        oc.ui_style_set_f32(.UI_SPACING, 32);

                        {
                            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("unselected")));
                            defer _ = oc.ui_box_end();

                            oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                            oc.ui_style_set_f32(.UI_SPACING, 16);

                            {
                                oc.ui_style_rule_begin(oc.to_str8(@constCast("radio-label")));
                                defer oc.ui_style_rule_end();

                                oc.ui_style_set_f32(.UI_TEXT_SIZE, 16);
                            }
                            _ = oc.ui_label(@constCast("radio-label"), @constCast("Radio style"));

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("size")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 4);

                                var widthSlider: f32 = (Unselected.width - 8) / 16;
                                labeled_slider("Width", &widthSlider);
                                Unselected.width = 8 + widthSlider * 16;

                                var heightSlider: f32 = (Unselected.height - 8) / 16;
                                labeled_slider("Height", &heightSlider);
                                Unselected.height = 8 + heightSlider * 16;

                                var roundnessSlider: f32 = (Unselected.roundness - 4) / 8;
                                labeled_slider("Roundness", &roundnessSlider);
                                Unselected.roundness = 4 + roundnessSlider * 8;
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("background")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 4);
                                labeled_slider("Background R", &Unselected.bgColor.r);
                                labeled_slider("Background G", &Unselected.bgColor.g);
                                labeled_slider("Background B", &Unselected.bgColor.b);
                                labeled_slider("Background A", &Unselected.bgColor.a);
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("border")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 4);
                                labeled_slider("Border R", &Unselected.borderColor.r);
                                labeled_slider("Border G", &Unselected.borderColor.g);
                                labeled_slider("Border B", &Unselected.borderColor.b);
                                labeled_slider("Border A", &Unselected.borderColor.a);
                            }

                            var borderSizeSlider: f32 = Unselected.borderSize / 5;
                            labeled_slider("Border size", &borderSizeSlider);
                            Unselected.borderSize = borderSizeSlider * 5;

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("status_override")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 10);
                                _ = oc.ui_label(@constCast("label"), @constCast("Override"));

                                const Status = struct {
                                    var index: i32 = 0;
                                };

                                const options = [_]oc.str8{
                                    oc.to_str8(@constCast("Always")),
                                    oc.to_str8(@constCast("When hovering")),
                                    oc.to_str8(@constCast("When active")),
                                };
                                var statusInfo: oc.ui_radio_group_info = .{
                                    .changed = false,
                                    .selectedIndex = Status.index,
                                    .optionCount = options.len,
                                    .options = @constCast(&options),
                                };
                                const result = oc.ui_radio_group(@constCast("status"), &statusInfo);
                                Status.index = result.selectedIndex;
                                Unselected.whenStatus = switch (Status.index) {
                                    0 => oc.to_str8(@constCast("")),
                                    1 => oc.to_str8(@constCast(".hover")),
                                    2 => oc.to_str8(@constCast(".active")),
                                    else => Unselected.whenStatus,
                                };
                            }
                        }

                        {
                            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("selected")));
                            defer _ = oc.ui_box_end();

                            oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                            oc.ui_style_set_f32(.UI_SPACING, 16);

                            {
                                oc.ui_style_rule_begin(oc.to_str8(@constCast("radio-label")));
                                defer oc.ui_style_rule_end();

                                oc.ui_style_set_f32(.UI_TEXT_SIZE, 16);
                            }
                            _ = oc.ui_label(@constCast("radio-label"), @constCast("Radio style"));

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("size")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 4);

                                var widthSlider: f32 = (Selected.width - 8) / 16;
                                labeled_slider("Width", &widthSlider);
                                Selected.width = 8 + widthSlider * 16;

                                var heightSlider: f32 = (Selected.height - 8) / 16;
                                labeled_slider("Height", &heightSlider);
                                Selected.height = 8 + heightSlider * 16;

                                var roundnessSlider: f32 = (Selected.roundness - 4) / 8;
                                labeled_slider("Roundness", &roundnessSlider);
                                Selected.roundness = 4 + roundnessSlider * 8;
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("background")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 4);
                                labeled_slider("Background R", &Selected.bgColor.r);
                                labeled_slider("Background G", &Selected.bgColor.g);
                                labeled_slider("Background B", &Selected.bgColor.b);
                                labeled_slider("Background A", &Selected.bgColor.a);
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("center")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 4);
                                labeled_slider("Center R", &Selected.centerColor.r);
                                labeled_slider("Center G", &Selected.centerColor.g);
                                labeled_slider("Center B", &Selected.centerColor.b);
                                labeled_slider("Center A", &Selected.centerColor.a);
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("spacer")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 24 }));
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("status_override")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                                oc.ui_style_set_f32(.UI_SPACING, 10);
                                _ = oc.ui_label(@constCast("label"), @constCast("Override"));

                                const Status = struct {
                                    var index: i32 = 0;
                                };

                                const options = [_]oc.str8{
                                    oc.to_str8(@constCast("Always")),
                                    oc.to_str8(@constCast("When hovering")),
                                    oc.to_str8(@constCast("When active")),
                                };
                                var statusInfo: oc.ui_radio_group_info = .{
                                    .changed = false,
                                    .selectedIndex = Status.index,
                                    .optionCount = options.len,
                                    .options = @constCast(&options),
                                };
                                const result = oc.ui_radio_group(@constCast("status"), &statusInfo);
                                Status.index = result.selectedIndex;
                                Selected.whenStatus = switch (Status.index) {
                                    0 => oc.to_str8(@constCast("")),
                                    1 => oc.to_str8(@constCast(".hover")),
                                    2 => oc.to_str8(@constCast(".active")),
                                    else => Selected.whenStatus,
                                };
                            }
                        }

                        {
                            _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("label")));
                            defer _ = oc.ui_box_end();

                            oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
                            oc.ui_style_set_f32(.UI_SPACING, 16);

                            {
                                oc.ui_style_rule_begin(oc.to_str8(@constCast("label-style")));
                                defer oc.ui_style_rule_end();

                                oc.ui_style_set_f32(.UI_TEXT_SIZE, 16);
                            }
                            _ = oc.ui_label(@constCast("label-style"), @constCast("Label style"));

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("font_color")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_f32(.UI_SPACING, 8);

                                {
                                    oc.ui_style_rule_begin(oc.to_str8(@constCast("font-color")));
                                    defer oc.ui_style_rule_end();

                                    oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 100 }));
                                }
                                _ = oc.ui_label(@constCast("font-color"), @constCast("Font color"));

                                const Color = struct {
                                    var selected: i32 = 0;
                                };

                                const colorNames = [_]oc.str8{
                                    oc.to_str8(@constCast("Default")),
                                    oc.to_str8(@constCast("Red")),
                                    oc.to_str8(@constCast("Orange")),
                                    oc.to_str8(@constCast("Amber")),
                                    oc.to_str8(@constCast("Yellow")),
                                    oc.to_str8(@constCast("Lime")),
                                    oc.to_str8(@constCast("Light Green")),
                                    oc.to_str8(@constCast("Green")),
                                };
                                const colors = [_]oc.color{
                                    .{ .r = 1, .g = 1, .b = 1, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 0.988, .g = 0.447, .b = 0.353, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 1.000, .g = 0.682, .b = 0.263, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 0.961, .g = 0.792, .b = 0.314, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 0.992, .g = 0.871, .b = 0.263, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 0.682, .g = 0.863, .b = 0.227, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 0.592, .g = 0.776, .b = 0.373, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                    .{ .r = 0.365, .g = 0.761, .b = 0.392, .a = 1, .colorSpace = .COLOR_SPACE_SRGB },
                                };
                                var colorInfo = std.mem.zeroInit(oc.ui_select_popup_info, .{
                                    .selectedIndex = Color.selected,
                                    .optionCount = colorNames.len,
                                    .options = @constCast(&colorNames),
                                });
                                const colorResult = oc.ui_select_popup(@constCast("color"), &colorInfo);
                                Color.selected = colorResult.selectedIndex;
                                Label.fontColor = colors[@intCast(Color.selected)];
                            }

                            {
                                _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("font")));
                                defer _ = oc.ui_box_end();

                                oc.ui_style_set_f32(.UI_SPACING, 8);

                                {
                                    oc.ui_style_rule_begin(oc.to_str8(@constCast("font-label")));
                                    defer oc.ui_style_rule_end();

                                    oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 100 }));
                                }
                                _ = oc.ui_label(@constCast("font-label"), @constCast("Font"));

                                const Font = struct {
                                    var selected: i32 = 0;
                                };

                                const fontNames = [_]oc.str8{
                                    oc.to_str8(@constCast("Regular")),
                                    oc.to_str8(@constCast("Bold")),
                                };
                                const fonts = [_]*oc.font{
                                    &font_regular,
                                    &font_bold,
                                };
                                var fontInfo = std.mem.zeroInit(oc.ui_select_popup_info, .{
                                    .selectedIndex = Font.selected,
                                    .optionCount = fontNames.len,
                                    .options = @constCast(&fontNames),
                                });
                                const fontResult = oc.ui_select_popup(@constCast("font_style"), &fontInfo);
                                Font.selected = fontResult.selectedIndex;
                                Label.font = fonts[@intCast(Font.selected)];
                            }

                            var fontSizeSlider: f32 = (Label.fontSize - 8) / 16;
                            labeled_slider("Font size", &fontSizeSlider);
                            Label.fontSize = 8 + fontSizeSlider * 16;
                        }
                    }
                }
            }
        }
    }

    _ = oc.canvas_context_select(canvas);

    oc.ui_draw();
    oc.canvas_render(renderer, canvas, surface);
    oc.canvas_present(renderer, surface);
}

fn log_pushf(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, fmt, args) catch @panic("OOM");
    log_push(line);
}

fn log_push(line: []const u8) void {
    oc.str8_list_push(&log_arena, &log_lines, oc.to_str8(@constCast(line)));
}

fn column_begin(header: [:0]const u8, widthFraction: f32) void {
    _ = oc.ui_box_begin_str8(oc.to_str8(@constCast(header)));

    oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = widthFraction, .relax = 1 }));
    oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
    oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
    oc.ui_style_set_f32(.UI_MARGIN_Y, 8);
    oc.ui_style_set_f32(.UI_SPACING, 24);
    oc.ui_style_set_var_str8(.UI_BG_COLOR, oc.to_str8(@constCast("bg-1")));
    oc.ui_style_set_var_str8(.UI_BORDER_COLOR, oc.to_str8(@constCast("border")));
    oc.ui_style_set_f32(.UI_BORDER_SIZE, 1);
    oc.ui_style_set_var_str8(.UI_ROUNDNESS, oc.to_str8(@constCast("roundness-small")));
    oc.ui_style_set_i32(.UI_CONSTRAIN_Y, 1);

    {
        _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("header")));
        defer _ = oc.ui_box_end();

        oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
        oc.ui_style_set_i32(.UI_ALIGN_X, @intFromEnum(oc.ui_align.UI_ALIGN_CENTER));

        {
            oc.ui_style_rule_begin(oc.to_str8(@constCast(".label")));
            defer oc.ui_style_rule_end();

            oc.ui_style_set_f32(.UI_TEXT_SIZE, 18);
        }
        _ = oc.ui_label(@constCast("label"), @constCast(header.ptr));
    }

    _ = oc.ui_box_begin_str8(oc.to_str8(@constCast("contents")));

    oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1 }));
    oc.ui_style_set_size(.UI_HEIGHT, ui_size(.{ .kind = .UI_SIZE_PARENT, .value = 1, .relax = 1 }));
    oc.ui_style_set_i32(.UI_AXIS, @intFromEnum(oc.ui_axis.UI_AXIS_Y));
    oc.ui_style_set_i32(.UI_ALIGN_X, @intFromEnum(oc.ui_align.UI_ALIGN_START));
    oc.ui_style_set_f32(.UI_MARGIN_X, 16);
    oc.ui_style_set_f32(.UI_SPACING, 24);
    oc.ui_style_set_i32(.UI_CONSTRAIN_Y, 1);
}

fn column_end() void {
    _ = oc.ui_box_end(); // contents
    _ = oc.ui_box_end(); // column
}

fn labeled_slider(label: [:0]const u8, value: *f32) void {
    _ = oc.ui_box_begin_str8(oc.to_str8(@constCast(label)));
    defer _ = oc.ui_box_end();

    oc.ui_style_set_f32(.UI_SPACING, 8);

    {
        oc.ui_style_rule_begin(oc.to_str8(@constCast("label")));
        defer oc.ui_style_rule_end();

        oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 100 }));
    }
    _ = oc.ui_label(@constCast("label"), @constCast(label));

    {
        oc.ui_style_rule_begin(oc.to_str8(@constCast("slider")));
        defer oc.ui_style_rule_end();

        oc.ui_style_set_size(.UI_WIDTH, ui_size(.{ .kind = .UI_SIZE_PIXELS, .value = 100 }));
    }
    _ = oc.ui_slider(@constCast("slider"), value);
}

fn oc_list_checked_entry(elt_ptr: ?*oc.list_elt, comptime T: type, comptime member: []const u8) ?*T {
    return if (elt_ptr) |elt| @as(*T, @fieldParentPtr(member, elt)) else null;
}

fn ui_size(s: anytype) oc.ui_size {
    return std.mem.zeroInit(oc.ui_size, s);
}
