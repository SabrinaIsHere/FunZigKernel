//! Use framebuffers as passed along by limine to display text for now and whatever else later
//! No immediate plans to support more than one framebuffer
//! This may need to move to userland at some point since, yk, microkernel
//! I wrote this without example code and I'm very proud of it

const arch = @import("../../arch.zig");
const main = @import("../../../../main.zig");
const limine = @import("limine");

/// Errors related to the video driver
const VideoError = error{
    NoFramebufferFound,
    NoValidVideoMode,
    InvalidBpp,
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
inline fn getPixel(x: u64, y: u64) u64 {
    return y * framebuffer.pitch + x * pixel_width;
}

/// This may be iterated on. Takes coordinates and sets the pixel at those coordinates to a
/// truncated value depending on bpp
pub fn setPixel(x: u64, y: u64, value: u64) void {
    for (0..pixel_width) |i| {
        // NOTE: This might be reversing the pixel
        framebuffer_addr[getPixel(x, y) + i] = @truncate(value >> @intCast(i * 8));
    }
}

/// Sets every byte underlying the pixels directly
/// This has error checking. Fails silently
pub fn setRange(x1: u64, x2: u64, y1: u64, y2: u64, value: u64) void {
    if (x2 > width or y2 > height) return;
    var y = y1;
    while (y < y2) : (y += 1) {
        var x = x1;
        while (x < x2) : (x += 1) setPixel(x, y, value);
    }
}

pub fn clear() void {
    setRange(0, width, 0, height, 0x0);
}
