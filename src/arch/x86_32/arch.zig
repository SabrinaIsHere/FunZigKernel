//! Got this from https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/arch.zig

const GDT = @import("GDT.zig");
const IDT = @import("IDT.zig");
const ISR = @import("ISR.zig");
const IO = @import("../../io/io.zig");
pub const Console = IO.Console;

/// Initializes architecture specific things like the GDT and IDT
pub fn init() void {
    GDT.init();
    IDT.init();
    ISR.init();
}

/// Wrapper for the x86 assembly instruction 'inb'
pub fn in(comptime Type: type, port: u16) Type {
    return switch (Type) {
        u8 => asm volatile ("inb %[port], %[result]"
            : [result] "={al}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u16 => asm volatile ("inw %[port], %[result]"
            : [result] "={ax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        u32 => asm volatile ("inl %[port], %[result]"
            : [result] "={eax}" (-> Type),
            : [port] "N{dx}" (port),
        ),
        else => @compileError("in: Valid types are u8, u16, and u32. Found " ++ @typeName(Type)),
    };
}

/// Wrapper for the x86 assembly instruction 'outb'
pub fn out(port: u16, val: anytype) void {
    switch (@TypeOf(val)) {
        u8 => asm volatile ("outb %[val], %[port]"
            :
            : [port] "{dx}" (port),
              [val] "{al}" (val),
        ),
        u16 => asm volatile ("outw %[val], %[port]"
            :
            : [port] "{dx}" (port),
              [val] "{ax}" (val),
        ),
        u32 => asm volatile ("outl %[val], %[port]"
            :
            : [port] "{dx}" (port),
              [val] "{eax}" (val),
        ),
        else => @compileError("out: Valid types are u8, u16, and u32. Found " ++ @typeName(@TypeOf(val))),
    }
}

// Enable interrupts
pub fn enableInterrupts() void {
    asm volatile ("sti");
}

// Disable interrupts
pub fn disableInterrupts() void {
    asm volatile ("cli");
}

/// Halt the processor
pub fn hlt() void {
    asm volatile ("hlt");
}

/// Kernel panic; disable interrupts and halt the cpu
pub fn k_panic(comptime msg: []const u8) noreturn {
    disableInterrupts();
    Console.print(msg, .{});
    while (true) hlt();
}
