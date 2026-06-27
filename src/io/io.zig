//! Presents hardware agnostic interfaces for IO

pub const arch = @import("../arch/arch.zig").arch;
const Drivers = arch.Drivers;
const Serial = Drivers.Serial;
const Framebuffer = Drivers.Framebuffer;
const PS2Keyboard = Drivers.PS2Keyboard;
const Font = @import("../misc/font.zig");
const VideoConsole = @import("video_console.zig");
const Terminal = @import("../terminal.zig");

/// Standard interface exposing console IO
pub const Console = struct {
    /// Initializes output modes (serial, framebuffer)
    pub fn init() void {
        Serial.init() catch arch.k_panic("Serial unable to initialize.");
        VideoConsole.init();
    }
    /// Initializes keyboard
    pub fn initInput() void {
        defer print("> ", .{});
        PS2Keyboard.init();
        PS2Keyboard.registerHandler(scancodeHandler);
        Terminal.init();
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
    /// Unified interface called by drivers handling data input
    pub fn registerKeypress(c: u8) void {
        // Full command gets printed to serial when it's entered
        VideoConsole.print("{c}", .{c});
        Terminal.registerChar(c);
        if (c == '\n') print("> ", .{});
    }
    /// Called by the keyboard driver
    pub fn scancodeHandler(code: PS2Keyboard.Scancode) void {
        // The one liners here are maybe ill advised but whatever. I wish I knew of a better way to do this
        switch (code) {
            .reg => if (code.reg.released) {
                if (PS2Keyboard.scancodeToAscii(code)) |c| {
                    registerKeypress(c);
                } else if (code.reg.char == .backspace) {
                    if (Terminal.backspace()) VideoConsole.backspace();
                }
            },
            .ex => if (code.ex.released) if (PS2Keyboard.scancodeToAscii(code)) |c| registerKeypress(c),
        }
    }
};
