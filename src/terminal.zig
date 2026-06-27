//! This file implements command parsing and the basic commands, but mostly an interface for other systems to register
//! a command. Long term, this is meant to support basic debugging but userspace code will replace this for most use
//!
//! TODO: Zig buffer allocator initiated with memory pulled from my allocator
//! TODO: Buffer size increasing as needed

const std = @import("std");
const main = @import("main.zig");
const arch = @import("arch/x86_64/arch.zig");
const Serial = arch.Drivers.Serial;
const Console = main.Console;
const print = Console.print;
const Framebuffer = arch.Drivers.Framebuffer;

pub const CommandErr = error{
    CommandNotFound,
    InvalidArgument,
};

pub const CommandFunc = *const fn (cmd_text: *const []u8) CommandErr!void;

/// Struct for other systems to cleanly register their commands
pub const Command = struct {
    /// Function run when the command is executed
    func: CommandFunc,
    /// Command to enter to run the above function
    string: []const u8,
    /// Displayed by the help command
    help_text: []const u8 = "",
};

/// Static array of command objects
/// Command objects are typically pulled from other files to make private functions less annoying
/// Initially I didn't wanna do it this way bc it clogs up the import statements but whatever
const commands = [_]Command{
    .{
        .func = testCommandFunc,
        .string = "test",
        .help_text = "Basic command meant to test the console",
    },
    .{
        .func = helpCommandFunc,
        .string = "help",
    },
    Framebuffer.cmd,
};
var cmd_buffer: std.ArrayList(u8) = .empty;

fn testCommandFunc(cmd_text: *const []u8) CommandErr!void {
    print("Test: {s}\n", .{cmd_text.*});
}

pub fn init() void {
    //commands.init(main.al, 30);
    //cmd_buffer.init(main.al, 30);
}

pub fn registerChar(char: u8) void {
    if (char != '\n') {
        cmd_buffer.append(main.al.?, char) catch @panic("registerChar: Out of memory");
        return;
    }
    // Keep serial updated
    Serial.print("{s}\n", .{cmd_buffer.items});
    // Look for and execute command if enter was just pressed
    for (commands) |cmd| {
        if (checkHasCommand(cmd, &cmd_buffer.items)) {
            cmd.func(&cmd_buffer.items[0..]) catch |err| print("{any}\n", .{err});
            break;
        }
    }
    cmd_buffer.clearAndFree(main.al.?);
}

/// Called by io.zig when it detects a backspace
/// Return value is whether or not anything has actually been typed
pub fn backspace() bool {
    return cmd_buffer.pop() != null;
}

/// Checks if the passed string starts with this command's string
pub fn checkHasCommand(cmd: Command, str: *[]u8) bool {
    if (str.len < cmd.string.len) return false;
    for (str.*, 0..) |c, i| {
        if (i >= cmd.string.len) break;
        if (cmd.string[i] != c) return false;
    }
    return true;
}

/// Basic help command's function
fn helpCommandFunc(cmd_text: *const []u8) CommandErr!void {
    _ = cmd_text;
    for (commands) |cmd| print("{s}: {s}\n", .{ cmd.string, cmd.help_text });
}
