//! Use framebuffers as passed along by limine to display text for now and whatever else later
//! No immediate plans to support more than one framebuffer
//! This may need to move to userland at some point since, yk, microkernel
//! I wrote this without example code and I'm very proud of it

const arch = @import("../../arch.zig");
const main = @import("../../../../main.zig");
const limine = @import("limine");
const Terminal = main.terminal;

/// Errors related to the video driver
const VideoError = error{
    NoFramebufferFound,
    NoValidVideoMode,
    InvalidBpp,
    InvalidCoordinates,
};

// TODO: Color

/// Framebuffer displayed to. Might support more than one eventually NOTE: This probably could be set compile time from main
var framebuffer: *limine.Framebuffer = undefined;
/// Address of the framebuffer is physical memory
var framebuffer_addr: [*]u8 = undefined;
/// Width in bytes of a pixel
var pixel_width: u16 = undefined;
/// Video mode. Not used for anything atm, may remove
var mode: *limine.VideoMode = undefined;
/// Height, in pixels, of the framebuffer
pub var height: u64 = 0;
/// Width, in pixels, of the framebuffer
pub var width: u64 = 0;

/// Initialize the framebuffer and handle errors
pub fn init() VideoError!void {
    const response = main.framebuffer_request.response orelse return VideoError.NoFramebufferFound;
    // Error cases
    if (response.framebuffer_count == 0) return VideoError.NoFramebufferFound;
    framebuffer = (response.framebuffers orelse return VideoError.NoFramebufferFound)[0];
    if (framebuffer.bpp % 8 != 0 or framebuffer.bpp > 64) return VideoError.InvalidBpp;
    const modes = framebuffer.getModes(response) catch return VideoError.NoValidVideoMode;
    // Initialize globals
    framebuffer_addr = @ptrCast(framebuffer.address);
    pixel_width = framebuffer.bpp / 8;
    mode = modes[0];
    height = framebuffer.height;
    width = framebuffer.width;
    clear();
}

/// Gets the index of a pixel given it's coordinates
/// This is not memory safe which is why it's private
/// Be careful about overflows
inline fn getPixelIndex(x: u64, y: u64) u64 {
    return y * framebuffer.pitch + x * pixel_width;
}

/// Get the value of the pixel at given coordinates
pub fn getPixel(x: u64, y: u64) VideoError!u64 {
    var retval: u64 = 0;
    if (x > width or y > height) return VideoError.InvalidCoordinates;
    for (0..pixel_width) |i| {
        // NOTE: This might be reversing the pixel
        retval |= @as(u64, framebuffer_addr[getPixelIndex(x, y) + i]) << @intCast(i * 8);
    }
    return retval;
    //return framebuffer_addr[getPixelIndex(x, y)];
}

/// This may be iterated on. Takes coordinates and sets the pixel at those coordinates to a
/// truncated value depending on bpp
pub fn setPixel(x: u64, y: u64, value: u64) VideoError!void {
    if (x > width or y > height) return VideoError.InvalidCoordinates;
    for (0..pixel_width) |i| {
        // NOTE: This might be reversing the pixel
        framebuffer_addr[getPixelIndex(x, y) + i] = @truncate(value >> @intCast(i * 8));
    }
}

/// Sets every byte underlying the pixels directly
/// This has error checking. Fails silently
pub fn setRange(x1: u64, x2: u64, y1: u64, y2: u64, value: u64) void {
    if (x2 > width or y2 > height) return;
    var y = y1;
    while (y < y2) : (y += 1) {
        var x = x1;
        while (x < x2) : (x += 1) setPixel(x, y, value) catch unreachable;
    }
}

/// Clears the framebuffer
pub fn clear() void {
    setRange(0, width, 0, height, 0x0);
}

/// Shifts the pixels between low and high up, inclusive of low and high
/// For both, any value less than 0 indexes from the bottom of the screen
/// TODO: Maybe amount is negative to shift down?
/// BUG: Negative coordinates don't work
pub fn shiftUp(low: isize, high: isize, amount: usize) VideoError!void {
    if (high < low) return VideoError.InvalidCoordinates;
    var y1: usize = @bitCast(if (low < 0) @as(i64, @bitCast(height)) + low + 1 else low);
    const y2: usize = @bitCast(if (high < 0) @as(i64, @bitCast(height)) + high + 1 else high);
    if (y1 > height) return VideoError.InvalidCoordinates;
    if (y2 > height) return VideoError.InvalidCoordinates;

    // Don't need to clear the last line if it copies black pixels
    while (y2 > y1) {
        for (0..width) |x| setPixel(
            x,
            y1,
            getPixel(x, y1 + amount) catch unreachable,
        ) catch unreachable;
        y1 += 1;
    }
}

// Command stuff

/// Object used by terminal.zig to execute the shift_up command
pub const shiftUpCmd = Terminal.Command{
    .func = shiftUpCmdFunc,
    .string = "shift_up",
    .help_text = "Shifts everything on screen up one row",
};

/// Function executed by the above command
fn shiftUpCmdFunc(cmd_text: *const []u8) Terminal.CommandErr!void {
    _ = cmd_text;
    shiftUp(0, 31, 8) catch @panic("Framebuffer coordinate error");
}
