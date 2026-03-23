//! Got this from https://github.com/ZystemOS/pluto/blob/develop/src/kernel/arch/x86/arch.zig

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
