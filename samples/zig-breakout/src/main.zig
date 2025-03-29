const std = @import("std");
const math = std.math;
const oc = @import("root");

const num_blocks_per_row = 7;
const num_blocks = num_blocks_per_row * 6;
const num_blocks_to_win = (num_blocks -| 2);
const blocks_width = 810.0;
const block_height = 30.0;
const blocks_padding = 15.0;
const blocks_bottom = 300.0;
const paddle_max_launch_angle = 0.7;

const block_width: f32 =
    (blocks_width - ((num_blocks_per_row + 1) * blocks_padding)) /
    @as(comptime_float, num_blocks_per_row);

var velocity: oc.vec2 = .{ .x = 5, .y = 5 };

// This is upside down from how it will actually be drawn.
var block_healths: [num_blocks]i32 = .{
    0, 1, 1, 1, 1, 1, 0,
    1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2,
    3, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3,
};

var score: i32 = 0;

var left_down: bool = false;
var right_down: bool = false;

var frame_size: oc.vec2 = .{ .x = 100, .y = 100 };

var surface: oc.surface = undefined;
var renderer: oc.canvas_renderer = undefined;
var canvas_ctx: oc.canvas_context = undefined;

var water_image: oc.image = undefined;
var brick_image: oc.image = undefined;
var ball_image: oc.image = undefined;
var font: oc.font = undefined;

const paddle_color: oc.color = .{ .r = 1, .g = 0, .b = 0, .a = 1, .colorSpace = .COLOR_SPACE_RGB };
var paddle: oc.rect = .{ .x = 300, .y = 50, .w = 200, .h = 24 };
var ball: oc.rect = .{ .x = 200, .y = 200, .w = 20, .h = 20 };

pub fn onInit() void {
    oc.window_set_title(oc.to_str8(@constCast("Breakout")));

    renderer = oc.canvas_renderer_create();
    surface = oc.canvas_surface_create(renderer);
    canvas_ctx = oc.canvas_context_create();

    water_image = oc.image_create_from_path(renderer, oc.to_str8(@constCast("/underwater.jpg")), false);
    brick_image = oc.image_create_from_path(renderer, oc.to_str8(@constCast("/brick.png")), false);
    ball_image = oc.image_create_from_path(renderer, oc.to_str8(@constCast("/ball.png")), false);

    if (oc.image_is_nil(water_image)) {
        oc.log.err("couldn't load water image", .{}, @src());
    }
    if (oc.image_is_nil(brick_image)) {
        oc.log.err("couldn't load brick image", .{}, @src());
    }
    if (oc.image_is_nil(ball_image)) {
        oc.log.err("couldn't load ball image", .{}, @src());
    }

    const ranges = [5]oc.unicode_range{
        .{ .firstCodePoint = 0x0000, .count = 127 }, // BASIC_LATIN
        .{ .firstCodePoint = 0x0080, .count = 127 }, // C1_CONTROLS_AND_LATIN_1_SUPPLEMENT
        .{ .firstCodePoint = 0x0100, .count = 127 }, // LATIN_EXTENDED_A
        .{ .firstCodePoint = 0x0180, .count = 207 }, // LATIN_EXTENDED_B
        .{ .firstCodePoint = 0xfff0, .count = 15 }, //  SPECIALS
    };

    font = oc.font_create_from_path(
        oc.to_str8(@constCast("/Literata-SemiBoldItalic.ttf")),
        @intCast(ranges.len),
        @constCast(&ranges),
    );
}

pub fn onTerminate() void {
    if (score == num_blocks_to_win) {
        oc.log.info("you win!", .{}, @src());
    } else {
        oc.log.info("goodbye world!", .{}, @src());
    }
}
pub fn onResize(width: u32, height: u32) void {
    oc.log.info("frame resize {d}, {d}", .{ width, height }, @src());
    frame_size.x = @floatFromInt(width);
    frame_size.y = @floatFromInt(height);
}

pub fn onKeyDown(_: oc.scan_code, key: oc.key_code) void {
    oc.log.info("key down: {s}", .{@tagName(key)}, @src());
    switch (key) {
        .KEY_LEFT => left_down = true,
        .KEY_RIGHT => right_down = true,
        else => {},
    }
}

pub fn onKeyUp(_: oc.scan_code, key: oc.key_code) void {
    oc.log.info("key up: {s}", .{@tagName(key)}, @src());
    switch (key) {
        .KEY_LEFT => left_down = false,
        .KEY_RIGHT => right_down = false,
        else => {},
    }
}

pub fn onFrameRefresh() void {
    const scratch = oc.scratch_begin();
    defer oc.arena_scope_end(scratch);

    if (left_down) {
        paddle.x -= 10;
    } else if (right_down) {
        paddle.x += 10;
    }
    paddle.x = math.clamp(paddle.x, 0, frame_size.x - paddle.w);

    ball.x += velocity.x;
    ball.y += velocity.y;
    ball.x = math.clamp(ball.x, 0, frame_size.x - ball.w);
    ball.y = math.clamp(ball.y, 0, frame_size.y - ball.h);

    if (ball.x + ball.w >= frame_size.x) {
        velocity.x = -velocity.x;
    }
    if (ball.x <= 0) {
        velocity.x = -velocity.x;
    }
    if (ball.y + ball.h >= frame_size.y) {
        velocity.y = -velocity.y;
    }

    if (ball.y <= paddle.y + paddle.h and
        ball.x + ball.w >= paddle.x and
        ball.x <= paddle.x + paddle.w and
        velocity.y < 0)
    {
        const t: f32 = ((ball.x + ball.w / 2) - paddle.x) / paddle.w;
        const launchAngle: f32 = math.lerp(-paddle_max_launch_angle, paddle_max_launch_angle, t);
        const speed: f32 = @sqrt(velocity.x * velocity.x + velocity.y * velocity.y);
        velocity = .{
            .x = @sin(launchAngle) * speed,
            .y = @cos(launchAngle) * speed,
        };
        ball.y = paddle.y + paddle.h;

        oc.log.info("PONG!", .{}, @src());
    }

    if (ball.y <= 0) {
        ball.x = frame_size.x / 2.0 - ball.w;
        ball.y = frame_size.y / 2.0 - ball.h;
    }

    for (&block_healths, 0..) |*health, i| {
        if (health.* <= 0) {
            continue;
        }

        const result = check_collision(block_rect(i));
        if (result != 0) {
            oc.log.info("Collision! direction={d}", .{result}, @src());
            health.* -= 1;

            if (health.* == 0) {
                score += 1;
            }

            const vx = velocity.x;
            const vy = velocity.y;

            switch (result) {
                1, 5 => {
                    velocity.y = -vy;
                    break;
                },
                3, 7 => {
                    velocity.x = -vx;
                    break;
                },
                2, 6 => {
                    velocity.x = -vy;
                    velocity.y = -vx;
                    break;
                },
                4, 8 => {
                    velocity.x = vy;
                    velocity.y = vx;
                    break;
                },
                else => {},
            }
        }
    }

    if (score == num_blocks_to_win) {
        oc.request_quit();
    }

    _ = oc.canvas_context_select(canvas_ctx);

    oc.set_color_rgba(10.0 / 255.0, 31.0 / 255.0, 72.0 / 255.0, 1);
    oc.clear();

    oc.image_draw(water_image, .{ .x = 0, .y = 0, .w = frame_size.x, .h = frame_size.y });

    const yUp: oc.mat2x3 = .{
        .m = .{
            1, 0,  0,
            0, -1, frame_size.y,
        },
    };

    oc.matrix_multiply_push(yUp);
    {
        for (&block_healths, 0..) |health, i| {
            if (health <= 0) {
                continue;
            }

            const r = block_rect(i);

            oc.set_image(brick_image);
            oc.set_color_rgba(0.9, 0.9, 0.9, 1);
            oc.rounded_rectangle_fill(r.x, r.y, r.w, r.h, 4);
            oc.set_image(oc.image_nil());

            oc.set_color_rgba(0.6, 0.6, 0.6, 1);
            oc.set_width(2);
            oc.rounded_rectangle_stroke(r.x, r.y, r.w, r.h, 4);

            const fontSize = 18;
            const text: oc.str8 = oc.str8_pushf(scratch.arena, @constCast("%d"), health);
            const textRect: oc.rect = oc.font_text_metrics(font, fontSize, text).ink;

            const textPos: oc.vec2 = .{
                .x = r.x + r.w / 2 - textRect.w / 2 - textRect.x,
                .y = r.y + r.h / 2 - textRect.h / 2 - textRect.y - textRect.h, //NOTE: we render with y-up so we need to flip bounding box coordinates.
            };

            oc.set_color_rgba(0.9, 0.9, 0.9, 1);
            oc.circle_fill(r.x + r.w / 2, r.y + r.h / 2, r.h / 2.5);

            oc.set_color_rgba(0, 0, 0, 1);
            oc.set_font(font);
            oc.set_font_size(18);
            oc.move_to(textPos.x, textPos.y);
            oc.matrix_multiply_push(flip_y_at(textPos));
            {
                oc.text_outlines(text);
                oc.fill();
            }
            oc.matrix_pop();
        }

        oc.set_color(paddle_color);
        oc.rounded_rectangle_fill(paddle.x, paddle.y, paddle.w, paddle.h, 4);

        oc.matrix_multiply_push(flip_y(ball));
        {
            oc.image_draw(ball_image, ball);
        }
        oc.matrix_pop();

        // draw score text
        {
            oc.move_to(20, 20);
            const text: oc.str8 = oc.str8_pushf(
                scratch.arena,
                @constCast("Destroy all %d blocks to win! Current score: %d"),
                @as(u32, num_blocks_to_win),
                score,
            );
            const textPos: oc.vec2 = .{ .x = 20, .y = 20 };
            oc.matrix_multiply_push(flip_y_at(textPos));
            {
                oc.set_color_rgba(0.9, 0.9, 0.9, 1);
                oc.text_outlines(text);
                oc.fill();
            }
            oc.matrix_pop();
        }
    }
    oc.matrix_pop();

    oc.canvas_render(renderer, canvas_ctx, surface);
    oc.canvas_present(renderer, surface);
}

fn block_rect(i: usize) oc.rect {
    const row: f32 = @floatFromInt(i / num_blocks_per_row);
    const col: f32 = @floatFromInt(i % num_blocks_per_row);
    return .{
        .x = blocks_padding + (blocks_padding + block_width) * col,
        .y = blocks_bottom + (blocks_padding + block_height) * row,
        .w = block_width,
        .h = block_height,
    };
}

/// Returns a cardinal direction 1-8 for the collision with the block, or zero
/// if no collision. 1 is straight up and directions proceed clockwise.
fn check_collision(block: oc.rect) u4 {
    // Note that all the logic for this game has the origin in the bottom left.

    const ball_x2: f32 = ball.x + ball.w;
    const ball_y2: f32 = ball.y + ball.h;
    const block_x2: f32 = block.x + block.w;
    const block_y2: f32 = block.y + block.h;

    if (ball_x2 < block.x or block_x2 < ball.x or
        ball_y2 < block.y or block_y2 < ball.y)
    {
        // Ball is fully outside block
        return 0;
    }

    // If moving right, the ball can bounce off its top right corner, right
    // side, or bottom right corner. Corner bounces occur if the block's bottom
    // left corner is in the ball's top right quadrant, or if the block's top
    // left corner is in the ball's bottom left quadrant. Otherwise, an edge
    // bounce occurs if the block's left edge falls in either of the ball's
    // right quadrants.
    //
    // This logic generalizes to other directions.
    //
    // We assume significant tunneling can't happen.

    const ball_center: oc.vec2 = .{
        .x = ball.x + ball.w / 2,
        .y = ball.y + ball.h / 2,
    };

    // Moving right
    if (velocity.x > 0) {
        // Ball's top right corner
        if (ball_center.x <= block.x and block.x <= ball_x2 and
            ball_center.y <= block.y and block.y <= ball_y2)
        {
            return 2;
        }

        // Ball's bottom right corner
        if (ball_center.x <= block.x and block.x <= ball_x2 and
            ball.y <= block_y2 and block_y2 <= ball_center.y)
        {
            return 4;
        }

        // Ball's right edge
        if (ball_center.x <= block.x and block.x <= ball_x2) {
            return 3;
        }
    }

    // Moving up
    if (velocity.y > 0) {
        // Ball's top left corner
        if (ball.x <= block_x2 and block_x2 <= ball_center.x and
            ball_center.y <= block.y and block.y <= ball_y2)
        {
            return 8;
        }

        // Ball's top right corner
        if (ball_center.x <= block.x and block.x <= ball_x2 and
            ball_center.y <= block.y and block.y <= ball_y2)
        {
            return 2;
        }

        // Ball's top edge
        if (ball_center.y <= block.y and block.y <= ball_y2) {
            return 1;
        }
    }

    // Moving left
    if (velocity.x < 0) {
        // Ball's bottom left corner
        if (ball.x <= block_x2 and block_x2 <= ball_center.x and
            ball.y <= block_y2 and block_y2 <= ball_center.y)
        {
            return 6;
        }

        // Ball's top left corner
        if (ball.x <= block_x2 and block_x2 <= ball_center.x and
            ball_center.y <= block.y and block.y <= ball_y2)
        {
            return 8;
        }

        // Ball's left edge
        if (ball.x <= block_x2 and block_x2 <= ball_center.x) {
            return 7;
        }
    }

    // Moving down
    if (velocity.y < 0) {
        // Ball's bottom right corner
        if (ball_center.x <= block.x and block.x <= ball_x2 and
            ball.y <= block_y2 and block_y2 <= ball_center.y)
        {
            return 4;
        }

        // Ball's bottom left corner
        if (ball.x <= block_x2 and block_x2 <= ball_center.x and
            ball.y <= block_y2 and block_y2 <= ball_center.y)
        {
            return 6;
        }

        // Ball's bottom edge
        if (ball.y <= block_y2 and block_y2 <= ball_center.y) {
            return 5;
        }
    }

    return 0;
}

fn flip_y(r: oc.rect) oc.mat2x3 {
    return .{ .m = .{
        1, 0,  0,
        0, -1, 2 * r.y + r.h,
    } };
}

fn flip_y_at(pos: oc.vec2) oc.mat2x3 {
    return .{ .m = .{
        1, 0,  0,
        0, -1, 2 * pos.y,
    } };
}
