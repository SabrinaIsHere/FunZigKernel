//! Got this from https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/arch.zig

pub const GDT = @import("GDT.zig");
pub const Cpuid = @import("cpuid.zig");
pub const Console = @import("console.zig");
pub const Paging = @import("paging.zig");

// General purpose registers
pub const Registers = packed struct {
    EAX: usize,
    EBX: usize,
    ECX: usize,
    EDX: usize,
    ESP: usize,
    EBP: usize,
    ESI: usize,
    EDI: usize,

    pub fn print(self: *Registers) void {
        Console.print(
            \\EAX: 0x{X}
            \\EBX: 0x{X}
            \\ECX: 0x{X}
            \\EDX: 0x{X}
            \\ESI: 0x{X}
            \\EDI: 0x{X}
            \\ESP: 0x{X}
            \\EBP: 0x{X}
            \\
        , .{
            self.EAX,
            self.EBX,
            self.ECX,
            self.EDX,
            self.ESI,
            self.EDI,
            self.ESP,
            self.EBP,
        });
    }
};

/// Wrapper for the x86 assembly instruction 'inb', asserts 8 bit type input
/// Anything returning Type needs to be title case according to the zig style guide
pub fn In(comptime Type: type, port: u16) linksection(".boottext") Type {
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

/// Wrapper for the x86 assembly instruction 'outb', asserts 8 bit type input
/// Anything returning Type needs to be title case according to the zig style guide
pub fn Out(port: u16, val: anytype) linksection(".boottext") void {
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

// Disable interrupts
pub fn disableInterrupts() linksection(".boottext") void {
    asm volatile ("cli");
}

/// Halt the processor
pub fn hlt() linksection(".boottext") void {
    asm volatile ("hlt");
}

/// Kernel panic; disable interrupts and halt the cpu
pub fn k_panic(comptime msg: []const u8) linksection(".boottext") noreturn {
    disableInterrupts();
    Console.print("kpanic: ", .{});
    Console.print(msg, .{});
    while (true) hlt();
}

pub inline fn setPAEEnabled() linksection(".boottext") void {
    asm volatile (
        \\ movl %%cr4, edx
        \\ orl %%edx, $(1 << 5)
        \\ movl %%edx, %%cr4
    );
}

pub inline fn setLMBit() linksection(".boottext") void {
    // Set the long mode bit
    asm volatile (
        \\ movl $0xC0000080, %%ecx
        \\ rdmsr
        \\ or %%eax, (1 << 9)
        \\ wrmsr
    );
}

pub inline fn enablePaging() linksection(".boottext") void {
    asm volatile (
        \\ movl %%cr0, %%eax
        \\ or %%eax, (1 << 31) | (1 << 0)
        \\ movl %%eax, %%cr0
    );
}

pub inline fn reloadSegmentRegs() linksection(".boottext") void {
    // NOTE: This probably won't work
    asm volatile (
        \\ movw $1, %%ax
        \\ movw %%ax, %%ds
        \\ movw %%ax, %%es
        \\ movw %%ax, %%fs
        \\ movw %%ax, %%gs
    );
}

pub inline fn setPML4(pml4: *Paging.PML4E) void {
    asm volatile (
        \\ movl %%eax, %%cr4
        :
        : [pml4] "{eax}" (pml4),
    );
}
