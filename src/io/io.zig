//! Presents hardware agnostic interfaces for IO

pub const arch = @import("../arch/arch.zig").arch;
const Drivers = arch.Drivers;
const Serial = Drivers.Serial;
const Framebuffer = Drivers.Framebuffer;
const Font = @import("../misc/font.zig");
const VideoConsole = @import("video_console.zig");

/// Standard interface exposing console IO
pub const Console = struct {
    /// Initializes output modes (serial, framebuffer)
    pub fn init() void {
        Serial.init() catch arch.k_panic("Serial unable to initialize.");
        VideoConsole.init();
    }
    // Clears video, doesn't clear serial since logs need to be maintained
    pub fn clear() void {
        VideoConsole.clear();
    }
    /// Prints to framebuffer and serial
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        Serial.print(fmt, args);
        VideoConsole.print(fmt, args);
    }
};
