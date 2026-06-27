//! Driver for the qemu default ps/2 device
//! This code doesn't need to be the most robust since it's just for qemu
//!
//! https://github.com/dreamportdev/Osdev-Notes/blob/master/02_Architecture/10_Keyboard_Interrupt_Handling.md
//!
//! 0x60 = data port
//! 0x64 = status/command register

const arch = @import("../../arch.zig");
const in = arch.in;
const out = arch.out;
const print = arch.Console.print;
const interrupts = arch.interrupts;
const APIC = arch.APIC;

const InterruptVector: u16 = 0x21;
const DataPort: u16 = 0x60;
const CmdPort: u16 = 0x64;

/// I know this is super gory but I can't think of a way around it, the code to get ascii is gonna be even worse
const ScancodeChar = enum(u7) { null, esc, one, two, three, four, five, six, seven, eight, nine, zero, minus, eq, backspace, tab, q, w, e, r, t, y, u, i, o, p, open_brace, close_brace, enter, l_control, a, s, d, f, g, h, j, k, l, semicolon, single_quote, back_tick, l_shift, backslash, z, x, c, v, b, n, m, comma, period, slash, r_shift, keypad_star, l_alt, space, caps_lock, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, numberlock, scrolllock, keypad_7, keypad_8, keypad_9, keypad_minus, keypad_4, keypad_5, keypad_6, keypad_plus, keypad_1, keypad_2, keypad_3, keypad_0, keypad_period };

const ExtendedScancodeChar = enum(u7) { prev_track = 0x10, next_track = 0x19, keypad_enter = 0x1c, r_control = 0x1d, mute = 0x20, calculator = 0x21, play = 0x22, stop = 0x24, vol_down = 0x2e, vol_up = 0x30, www_home = 0x32, keypad_slash = 0x35, right_alt = 0x38, home = 0x47, cursor_up = 0x48, page_up = 0x49, cursor_left = 0x4b, cursor_right = 0x4d, end = 0x4f, cursor_down = 0x50, page_down = 0x51, insert = 0x52, delete = 0x53, left_gui = 0x5b, right_gui = 0x5c, apps = 0x5d, acpi_power = 0x5e, acpi_sleep = 0x5f, acpi_wake = 0x63, www_search = 0x65, www_favs = 0x66, www_refresh = 0x67, www_stop = 0x68, www_forward = 0x69, www_back = 0x6a, my_computer = 0x6b, email = 0x6c, media_select = 0x6d };

/// More legible interpretation of raw scancode feedback
const RegularScancode = packed struct(u8) {
    /// What character it is
    char: ScancodeChar,
    /// If this is a make or break code
    released: bool,
};

/// I wanted to keep this unified with the other scancode struct but it would have been crazy ugly
const ExtendedScancode = packed struct(u8) {
    char: ExtendedScancodeChar,
    released: bool,
};

pub const Scancode = union(enum) {
    reg: RegularScancode,
    ex: ExtendedScancode,
};

/// Sets of possible scancodes, meant to be passed to the function that interacts with the device
/// NOTE: Devices are always compatible with set 2 and set 2 can usually be translated to set 1
const ScancodeSet = enum(u2) {
    getCurrent,
    set1,
    set2,
    set3,
};

pub const Handler = *const fn (Scancode) void;

/// Handles Initializing the device and collating information about it
const PS2Keyboard = struct {
    /// Whether or not set 2 scancodes are translated by the ps/2 controller
    scancodeTranslation: bool = false,
    scancodeSet: ScancodeSet = .getCurrent,
    /// Waiting for an interrupt with the extended scancode byte
    waitingOnExtended: bool = false,

    /// Gather information about the device and set it up
    /// TODO: I think some of this stuff needs to be split off into other functions
    pub fn init(self: *PS2Keyboard) void {
        // Get scancode set
        out(DataPort, @as(u8, 0xF0));
        out(DataPort, @as(u8, 0));
        // TODO: Proper error handling of absent ps2 keyboard
        if (in(u8, DataPort) != 0xFA) @panic("PS2 Keyboard invalid");
        const scancode_byte = in(u8, DataPort);
        switch (scancode_byte) {
            0x43 => self.scancodeSet = .set1,
            0x41 => self.scancodeSet = .set2,
            0x3F => self.scancodeSet = .set3,
            else => {},
        }
        if (self.scancodeSet == .set3) {
            out(DataPort, @as(u8, 0xF0));
            // Set scancode to 2 and translate
            out(DataPort, @as(u8, 0x2));
        }
        // Get translation info
        out(CmdPort, @as(u8, 0x20));
        // This is a mess but whatever it's only for qemu
        self.scancodeTranslation = (in(u8, DataPort) & 0b100000) >= 1;
        if (self.scancodeTranslation and self.scancodeSet == .set2) {
            self.scancodeSet = .set1;
        } else if (!self.scancodeTranslation and self.scancodeSet == .set2) {
            out(CmdPort, @as(u8, 0x20));
            const status_byte = in(u8, DataPort);
            out(CmdPort, @as(u8, 0x60));
            out(DataPort, status_byte | 0b100000);
            self.scancodeTranslation = true;
        }
        // Is this driver compatible
        if (self.scancodeSet != .set1) @panic("PS2 Keyboard invalid");
    }

    /// Meant to be called by the interrupt handler
    pub fn getScancode(self: *PS2Keyboard) ?Scancode {
        const code = in(u8, DataPort);
        // If not extended, return
        if (code == 0xE0) {
            self.waitingOnExtended = true;
            return null;
        }
        if (self.waitingOnExtended) {
            self.waitingOnExtended = false;
            return Scancode{ .ex = @bitCast(code) };
        }
        return Scancode{ .reg = @bitCast(code) };
    }
};

/// I know the semi object oriented thing going on here is awkward but I prefer the way this is organized over
/// having a bunch of functions in the file
pub var keyboard: PS2Keyboard = undefined;

/// Initialize the keyboard
pub fn init() void {
    defer print("Keyboard initialized\n", .{});
    interrupts.register(dummyHandler, InterruptVector);
    // Initialize device
    keyboard.init();
    // Register the low level direct interrupt handler
    interrupts.handlers[InterruptVector] = interruptHandler;
    //interrupts.register(handler, InterruptVector);
}

var handlers: [256]?Handler = [_]?Handler{null} ** 256;
var numHandlers: u16 = 0;

/// Handler code is too high level for this file so other files with register code to run
/// Multiple handlers can be registered
pub fn registerHandler(handler: Handler) void {
    handlers[numHandlers] = handler;
    numHandlers += 1;
}

var shiftActive: bool = false;

/// Runs other handlers
pub fn interruptHandler(ctx: *interrupts.CTX) void {
    _ = ctx;
    if (keyboard.getScancode()) |code| {
        //print("Scancode: {any}\n", .{code});
        //if (scancodeToAscii(code)) |c| print("{c}\n", .{c});
        // Call registered high level handlers
        switch (code) {
            .reg => |reg_code| if (reg_code.char == .l_shift or reg_code.char == .r_shift) {
                shiftActive = !reg_code.released;
            },
            .ex => {},
        }
        for (0..numHandlers) |i| if (handlers[i]) |handler| handler(code);
    }
    APIC.sendEOI();
}

/// Registered first so my code can work since the keyboard wants to sent interrupts while I'm getting the scancode set
pub fn dummyHandler(ctx: *interrupts.CTX) void {
    _ = ctx;
    APIC.sendEOI();
}

/// Get the ascii character associated with a scancode. Will be null if no character is associated (i.e. left control)
/// enter = \n
pub fn scancodeToAscii(code: Scancode) ?u8 {
    const char = switch (code) {
        .reg => |reg_code| regScancodeToAscii(reg_code),
        .ex => |ex_code| exScancodeToAscii(ex_code),
    };
    if (char) |c| if (shiftActive) return asciiToUppercase(c);
    return char;
}

fn regScancodeToAscii(code: RegularScancode) ?u8 {
    return switch (code.char) {
        .one => '1',
        .two => '2',
        .three => '3',
        .four => '4',
        .five => '5',
        .six => '6',
        .seven => '7',
        .eight => '8',
        .nine => '9',
        .zero => '0',
        .minus => '-',
        .eq => '=',
        .tab => '\t',
        .q => 'q',
        .w => 'w',
        .e => 'e',
        .r => 'r',
        .t => 't',
        .y => 'y',
        .u => 'u',
        .i => 'i',
        .o => 'o',
        .p => 'p',
        .open_brace => '[',
        .close_brace => ']',
        .enter => '\n',
        .a => 'a',
        .s => 's',
        .d => 'd',
        .f => 'f',
        .g => 'g',
        .h => 'h',
        .j => 'j',
        .k => 'k',
        .l => 'l',
        .semicolon => ';',
        .single_quote => '\'',
        .back_tick => '`',
        .backslash => '\\',
        .z => 'z',
        .x => 'x',
        .c => 'c',
        .v => 'v',
        .b => 'b',
        .n => 'n',
        .m => 'm',
        .comma => ',',
        .period => '.',
        .slash => '/',
        .keypad_star => '*',
        .space => ' ',
        .keypad_7 => '7',
        .keypad_8 => '8',
        .keypad_9 => '9',
        .keypad_minus => '-',
        .keypad_4 => '4',
        .keypad_5 => '5',
        .keypad_6 => '6',
        .keypad_plus => '+',
        .keypad_1 => '1',
        .keypad_2 => '2',
        .keypad_3 => '3',
        .keypad_0 => '0',
        .keypad_period => '.',
        else => null,
    };
}

fn exScancodeToAscii(code: ExtendedScancode) ?u8 {
    return switch (code.char) {
        .keypad_enter => '\n',
        .keypad_slash => '/',
        else => null,
    };
}

/// Handles special characters as well as standard
/// NOTE: In the future a more modular layout system will need to be in place
fn asciiToUppercase(c: u8) u8 {
    return switch (c) {
        '0' => ')',
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        'a'...'z' => c - 0x20,
        ';' => ':',
        '\'' => '\"',
        ',' => '<',
        '.' => '>',
        '/' => '?',
        '[' => '{',
        ']' => '}',
        '\\' => '|',
        '-' => '_',
        '=' => '+',
        '`' => '~',
        else => c,
    };
}
