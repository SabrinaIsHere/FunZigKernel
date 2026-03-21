//! Presents hardware agnostic interfaces for IO

/// Standard interface exposing console IO
pub const Console = struct {
    const VGA = @import("../drivers/display/vga.zig");
    pub const init = VGA.init;
    pub const print = VGA.print;
};
