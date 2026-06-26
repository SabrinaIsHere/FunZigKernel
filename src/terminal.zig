//! This file implements command parsing and the basic commands, but mostly an interface for other systems to register
//! a command. Long term, this is meant to support basic debugging but userspace code will replace this for most use
//!
//! TODO: Zig buffer allocator initiated with memory pulled from my allocator
//! TODO: Buffer size increasing as needed

const std = @import("std");
const main = @import("main.zig");
const Console = main.Console;
const print = Console.print;

const CommandErr = error{
    CommandNotFound,
    InvalidArgument,
};

const CommandFunc = *const fn (cmd_text: *const []u8) CommandErr!void;

/// Struct for other systems to cleanly register their commands
const Command = struct {
    func: CommandFunc,
    string: []const u8,
};

var commands: std.ArrayList(Command) = .empty;
var cmd_buffer: std.ArrayList(u8) = .empty;

fn testCommandFunc(cmd_text: *const []u8) CommandErr!void {
    print("Test: {s}\n", .{cmd_text.*});
}

const testCmd = Command{
    .func = testCommandFunc,
    .string = "test",
};

pub fn init() void {
    //commands.init(main.al, 30);
    //cmd_buffer.init(main.al, 30);
    //registerCommand(&testCmd);
    registerCommand(Command{
        .func = testCommandFunc,
        .string = "test",
    });
}

// TODO: This should be comptime
pub fn registerCommand(cmd: Command) void {
    commands.append(main.al.?, cmd) catch @panic("registerCommand: Out of memory");
}

pub fn registerChar(char: u8) void {
    if (char != '\n') {
        cmd_buffer.append(main.al.?, char) catch @panic("registerChar: Out of memory");
        return;
    }
    // Look for and execute command if enter was just pressed
    for (commands.items) |cmd| {
        if (checkHasCommand(cmd, &cmd_buffer.items)) {
            cmd.func(&cmd_buffer.items[0..]) catch |err| print("{any}\n", .{err});
            break;
        }
    }
    // This is probably the issue
    cmd_buffer.clearAndFree(main.al.?);
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
