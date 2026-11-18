const std = @import("std");
const posix = std.posix;

// ============================================
//  TRY CHANGING THESE!
// ============================================
const BOARD_WIDTH: u16 = 30;
const BOARD_HEIGHT: u16 = 20;
const INITIAL_SPEED_MS: u64 = 150; // lower = faster
const SNAKE_CHAR: []const u8 = "█";
const FOOD_CHAR: []const u8 = "●";
const SNAKE_COLOR: []const u8 = "\x1b[34m"; // blue
const FOOD_COLOR: []const u8 = "\x1b[31m"; // red
const BORDER_COLOR: []const u8 = "\x1b[36m"; // cyan
// ============================================

const RESET: []const u8 = "\x1b[0m";
const BOLD: []const u8 = "\x1b[1m";
const MAX_SNAKE_LEN = @as(usize, BOARD_WIDTH) * @as(usize, BOARD_HEIGHT);

// Each cell is 2 chars wide. Frame buffer needs room for the full board + borders + escape codes.
// Generous allocation: (BOARD_WIDTH*2 + 20) * (BOARD_HEIGHT + 4) * 4 bytes for escape codes
const FRAME_BUF_SIZE = (@as(usize, BOARD_WIDTH) * 2 + 40) * (@as(usize, BOARD_HEIGHT) + 6) * 4;

const Direction = enum { up, down, left, right };

const Point = struct {
    x: i16,
    y: i16,

    fn eql(a: Point, b: Point) bool {
        return a.x == b.x and a.y == b.y;
    }
};

// --- Game state ---
var snake: [MAX_SNAKE_LEN]Point = undefined;
var snake_len: usize = 0;
var direction: Direction = .right;
var next_direction: Direction = .right;
var food: Point = .{ .x = 0, .y = 0 };
var score: u32 = 0;
var game_over: bool = false;
var wants_quit: bool = false;
var prng: std.Random.DefaultPrng = undefined;
var orig_termios: posix.termios = undefined;

// --- Entry point ---

pub fn main() !void {
    const stdout = std.fs.File.stdout();
    const stdin_fd = std.fs.File.stdin().handle;

    // The game needs an interactive terminal for keyboard input
    if (!posix.isatty(stdin_fd)) {
        try stdout.writeAll("This game needs an interactive terminal.\nRun it directly: zig build run\n");
        return;
    }

    // Seed the random number generator from the system clock
    prng = std.Random.DefaultPrng.init(@as(u64, @bitCast(std.time.milliTimestamp())));

    // Switch terminal to raw mode so we can read keypresses directly
    orig_termios = try posix.tcgetattr(stdin_fd);
    var raw = orig_termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    raw.oflag.OPOST = false;
    raw.cflag.CSIZE = .CS8;
    raw.cc[@intFromEnum(posix.V.MIN)] = 0;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    try posix.tcsetattr(stdin_fd, .FLUSH, raw);
    defer posix.tcsetattr(stdin_fd, .FLUSH, orig_termios) catch {};

    // Hide cursor and clear screen
    try stdout.writeAll("\x1b[?25l\x1b[2J");
    defer stdout.writeAll("\x1b[?25h\x1b[0m") catch {};

    // Outer loop supports restarting the game
    while (!wants_quit) {
        try stdout.writeAll("\x1b[2J");
        initGame();
        try render(stdout);

        // --- Game tick loop ---
        while (!game_over and !wants_quit) {
            const frame_start = std.time.milliTimestamp();

            // Collect input for the duration of one tick
            while (true) {
                const now = std.time.milliTimestamp();
                const elapsed = now - frame_start;
                if (elapsed >= @as(i64, @intCast(INITIAL_SPEED_MS))) break;

                const remaining: i32 = @intCast(@as(i64, @intCast(INITIAL_SPEED_MS)) - elapsed);
                if (pollInput(stdin_fd, remaining)) {
                    readAndProcessInput(stdin_fd);
                } else {
                    break;
                }
            }

            // Apply the buffered direction change and advance the game
            direction = next_direction;
            update();
            if (!game_over) try render(stdout);
        }

        if (wants_quit) return;

        // Show final frame with the game-over overlay
        try render(stdout);
        try renderGameOver(stdout);

        // Wait for R (restart) or Q (quit)
        while (true) {
            _ = pollInput(stdin_fd, -1);
            var buf: [16]u8 = undefined;
            const n = std.fs.File.stdin().read(&buf) catch continue;
            if (n > 0) {
                if (buf[0] == 'r' or buf[0] == 'R') break;
                if (buf[0] == 'q' or buf[0] == 'Q') return;
            }
        }
    }
}

// --- Game logic ---

fn initGame() void {
    const cx: i16 = @intCast(BOARD_WIDTH / 2);
    const cy: i16 = @intCast(BOARD_HEIGHT / 2);

    // Start with a 3-segment snake in the middle, heading right
    snake_len = 3;
    snake[0] = .{ .x = cx, .y = cy };
    snake[1] = .{ .x = cx - 1, .y = cy };
    snake[2] = .{ .x = cx - 2, .y = cy };

    direction = .right;
    next_direction = .right;
    score = 0;
    game_over = false;

    spawnFood();
}

fn spawnFood() void {
    const rand = prng.random();
    // Keep trying random positions until we find one not on the snake
    while (true) {
        const fx = rand.intRangeLessThan(i16, 0, @as(i16, BOARD_WIDTH));
        const fy = rand.intRangeLessThan(i16, 0, @as(i16, BOARD_HEIGHT));
        const candidate = Point{ .x = fx, .y = fy };

        var on_snake = false;
        for (snake[0..snake_len]) |seg| {
            if (seg.eql(candidate)) {
                on_snake = true;
                break;
            }
        }
        if (!on_snake) {
            food = candidate;
            return;
        }
    }
}

fn update() void {
    var new_head = snake[0];
    switch (direction) {
        .up => new_head.y -= 1,
        .down => new_head.y += 1,
        .left => new_head.x -= 1,
        .right => new_head.x += 1,
    }

    // Wall collision
    if (new_head.x < 0 or new_head.x >= BOARD_WIDTH or
        new_head.y < 0 or new_head.y >= BOARD_HEIGHT)
    {
        game_over = true;
        return;
    }

    // Self collision (skip the tail — it will move away)
    for (snake[0 .. snake_len - 1]) |seg| {
        if (seg.eql(new_head)) {
            game_over = true;
            return;
        }
    }

    const ate_food = new_head.eql(food);

    if (ate_food) {
        // Grow: shift all segments back, then place the new head
        var i: usize = snake_len;
        while (i > 0) : (i -= 1) {
            snake[i] = snake[i - 1];
        }
        snake_len += 1;
        score += 10;
        spawnFood();
    } else {
        // Move: shift body, the tail disappears
        var i: usize = snake_len - 1;
        while (i > 0) : (i -= 1) {
            snake[i] = snake[i - 1];
        }
    }

    snake[0] = new_head;
}

// --- Input handling ---

fn readAndProcessInput(fd: posix.fd_t) void {
    var buf: [16]u8 = undefined;
    const n = posix.read(fd, &buf) catch return;
    if (n == 0) return;

    // Arrow keys send: ESC [ A/B/C/D
    if (n >= 3 and buf[0] == 0x1b and buf[1] == '[') {
        switch (buf[2]) {
            'A' => {
                if (direction != .down) next_direction = .up;
            },
            'B' => {
                if (direction != .up) next_direction = .down;
            },
            'C' => {
                if (direction != .left) next_direction = .right;
            },
            'D' => {
                if (direction != .right) next_direction = .left;
            },
            else => {},
        }
        return;
    }

    switch (buf[0]) {
        'q', 'Q' => wants_quit = true,
        'w', 'W' => {
            if (direction != .down) next_direction = .up;
        },
        'a', 'A' => {
            if (direction != .right) next_direction = .left;
        },
        's', 'S' => {
            if (direction != .up) next_direction = .down;
        },
        'd', 'D' => {
            if (direction != .left) next_direction = .right;
        },
        else => {},
    }
}

fn pollInput(fd: posix.fd_t, timeout_ms: i32) bool {
    var fds = [_]posix.pollfd{
        .{ .fd = fd, .events = posix.POLL.IN, .revents = 0 },
    };
    const n = posix.poll(&fds, timeout_ms) catch return false;
    return n > 0;
}

// --- Rendering ---

fn render(stdout: std.fs.File) !void {
    var frame_buf: [FRAME_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&frame_buf);
    const w = fbs.writer();

    // Move cursor to top-left (overwrite the previous frame)
    try w.writeAll("\x1b[H");

    // Score line
    try w.writeAll(RESET);
    try w.print("  Score: {d}  \n\r", .{score});

    // Top border: ┌──...──┐
    try w.writeAll(BORDER_COLOR);
    try w.writeAll("  ┌");
    for (0..BOARD_WIDTH) |_| try w.writeAll("──");
    try w.writeAll("┐\n\r");

    // Board rows
    var y: i16 = 0;
    while (y < BOARD_HEIGHT) : (y += 1) {
        try w.writeAll(BORDER_COLOR);
        try w.writeAll("  │");

        var x: i16 = 0;
        while (x < BOARD_WIDTH) : (x += 1) {
            const p = Point{ .x = x, .y = y };

            if (snakeIndex(p)) |idx| {
                // Bright head, normal body
                if (idx == 0) try w.writeAll(BOLD);
                try w.writeAll(SNAKE_COLOR);
                try w.writeAll(SNAKE_CHAR);
                try w.writeAll(" ");
                if (idx == 0) try w.writeAll(RESET);
            } else if (p.eql(food)) {
                try w.writeAll(FOOD_COLOR);
                try w.writeAll(FOOD_CHAR);
                try w.writeAll(" ");
            } else {
                try w.writeAll("  ");
            }
        }

        try w.writeAll(BORDER_COLOR);
        try w.writeAll("│\n\r");
    }

    // Bottom border: └──...──┘
    try w.writeAll(BORDER_COLOR);
    try w.writeAll("  └");
    for (0..BOARD_WIDTH) |_| try w.writeAll("──");
    try w.writeAll("┘\n\r");

    // Controls hint
    try w.writeAll(RESET);
    try w.writeAll("  Arrow keys / WASD to move | Q to quit\n\r");

    // Write the entire frame at once (prevents flicker)
    try stdout.writeAll(fbs.getWritten());
}

fn renderGameOver(stdout: std.fs.File) !void {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const w = fbs.writer();

    // Position the overlay in the center of the board
    const cy: u16 = BOARD_HEIGHT / 2 + 2;
    const cx: u16 = BOARD_WIDTH + 2;

    try w.print("\x1b[{d};{d}H", .{ cy, cx - 6 });
    try w.writeAll("\x1b[41;37;1m  GAME OVER!  " ++ RESET);

    try w.print("\x1b[{d};{d}H", .{ cy + 2, cx - 8 });
    try w.print(BOLD ++ "  Final Score: {d}  " ++ RESET, .{score});

    try w.print("\x1b[{d};{d}H", .{ cy + 4, cx - 14 });
    try w.writeAll("  Press " ++ BOLD ++ "R" ++ RESET ++ " to restart | " ++ BOLD ++ "Q" ++ RESET ++ " to quit  ");

    // Park cursor below the board
    try w.print("\x1b[{d};1H", .{@as(u16, BOARD_HEIGHT) + 5});

    try stdout.writeAll(fbs.getWritten());
}

fn snakeIndex(p: Point) ?usize {
    for (snake[0..snake_len], 0..) |seg, i| {
        if (seg.eql(p)) return i;
    }
    return null;
}
