//! Presents hardware agnostic interfaces for IO

/// Standard interface exposing console IO
pub const Console = struct {
    // TODO this should import Drivers and VGA through that
    const VGA = @import("../drivers/display/vga.zig");
    pub const init = VGA.init;
    pub const clear = VGA.clear;
    pub const print = VGA.print;
};
