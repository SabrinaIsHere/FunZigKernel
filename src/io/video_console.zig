//! Print text to a hardware driver
//! Deals with the actual rendering of text where the hardware driver does the bare minimum and just handles pixels
//! All code related to video rendering was written without example code which I personally am proud of
//! TODO: Cursor
//! TODO: Colors (gonna need some funky underlying struct to deal with bpp nonsense)
//! TODO: Delete (gonna have to wait on the cursor)

const std = @import("std");
const IO = @import("io.zig");
const arch = IO.arch;
const Drivers = arch.Drivers;
const Framebuffer = Drivers.Framebuffer;
const Font = @import("../misc/font.zig");
const Terminal = @import("../terminal.zig");

/// Number of pixels on each side of a letter
const letter_quantum = 8;
/// Keeps track of where the next letter should be printed. Letter coordinates, not pixel
var x: usize = 0;
/// Keeps track of where the next letter should be printed. Letter coordinates, not pixel
var y: usize = 0;
/// Maximum value y can safely be
var max_x: usize = 0;
/// Maximum value x can safely be
var max_y: usize = 0;

/// Initializes the font and fromebuffer as well as some constants
pub fn init() void {
    Font.init() catch arch.k_panic("Font could not initialize\n");
    Framebuffer.init() catch arch.k_panic("Framebuffer driver could not initialize\n");
    max_x = Framebuffer.width / letter_quantum;
    max_y = Framebuffer.height / letter_quantum;
}

/// Clears screen
pub fn clear() void {
    Framebuffer.clear();
    x = 0;
    y = 0;
}

/// Essentially a newline
fn incrementY() void {
    if (y + 1 >= max_y) {
        Framebuffer.shiftUp(0, @bitCast((y * letter_quantum) - 1), letter_quantum) catch @panic("Framebuffer coordinate error");
        y -= 1;
        x = 0;
    } else {
        y += 1;
        x = 0;
    }
}

/// Move x to the next spot, newline if running out of room
fn incrementX() void {
    if (x + 1 >= max_x) {
        incrementY();
    } else {
        x += 1;
    }
}

/// Print a single character to the console
fn printChar(c: u8) void {
    if (c == '\n') {
        incrementY();
        return;
    }
    if (c == '\t') {
        // If tab would wrap, newline and increment
        // This may need to change it's kind of weird
        if (x + 4 >= max_x) incrementY();
        x += 4;
        return;
    }
    const bitmap = Font.getBitmap(c);
    for (bitmap, 0..) |row, row_index| {
        var col: u8 = 0;
        while (col < 8) : (col += 1) {
            // Really hate how fiddly bitwise is in zig
            const val: u64 = switch (row & (@as(u8, 1) << @truncate(8 - col))) {
                0 => 0,
                else => 0xFFFFFFFFFFFFFFFF, // TODO: Colors
            };
            Framebuffer.setPixel(x * letter_quantum + col, y * letter_quantum + row_index, val) catch unreachable;
        }
    }
    incrementX();
}

/// Called by io.zig when it detects the scancode
pub fn backspace() void {
    // This assumes if you're at the beginning of a line you've just run a command and can't backspace
    // This is incorrect if you've just typed in enough to wrap but that's rare and probably not worth designing around rn
    if (x == 0) return;
    // Ik this is kinda hackey but whatever lol
    x -= 1;
    printChar(' ');
    x -= 1;
}

/// Print a string to the console
pub fn printString(s: []const u8) void {
    for (s) |c| printChar(c);
}

/// Print a string at the specified location
/// If line is negative index from the bottom of the screen, python style
pub fn printStringAt(s: []const u8, line: i32) void {
    const temp_y = y;
    const temp_x = x;
    y = if (line < 0) max_y + line + 1 else line;
    printString(s);
    y = temp_y;
    x = temp_x;
}

/// Drains buffer
/// Not written by me, came as part of the bare bones code on OSDev wiki
fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
    // the length of data must not be zero
    std.debug.assert(data.len != 0);

    var consumed: usize = 0;
    const pattern = data[data.len - 1];
    const splat_len = pattern.len * splat;

    // If buffer is not empty write it first
    if (w.end != 0) {
        printString(w.buffered());
        w.end = 0;
    }

    // Now write all data except last element
    for (data[0 .. data.len - 1]) |bytes| {
        printString(bytes);
        consumed += bytes.len;
    }

    // If out patter (i.e. last element of data) is non zero len then write splat times
    switch (pattern.len) {
        0 => {},
        else => {
            for (0..splat) |_| {
                printString(pattern);
            }
        },
    }
    // Now we have to return how many bytes we consumed from data
    consumed += splat_len;
    return consumed;
}

/// Returns std.Io.Writer implementation for this console
/// Not written by me, came as part of the bare bones code on OSDev wiki
pub fn writer(buffer: []u8) std.Io.Writer {
    return .{
        .buffer = buffer,
        .end = 0,
        .vtable = &.{
            .drain = drain,
        },
    };
}

/// Standard printing with format
/// Not written by me, came as part of the bare bones code on OSDev wiki
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var w = writer(&.{});
    w.print(fmt, args) catch return;
}

// Commands

/// Referenced by terminal.zig to execute this command
/// This could probably go in io.zig but there's no good reason telling me to go either way with it
pub const clearCmd = Terminal.Command{
    .func = clearCmdFunc,
    .string = "clear",
    .help_text = "Clears the screen",
};

/// Function executed by the above command
fn clearCmdFunc(cmd_text: *const []u8) Terminal.CommandErr!void {
    _ = cmd_text;
    clear();
}
