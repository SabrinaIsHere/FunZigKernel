const native_endian = @import("builtin").target.cpu.arch.endian();
const arch = @import("arch.zig");
const Console = arch.Console;

// Base address of the GDT table
pub const GDT: [3]GDTEntry linksection(".bootrodata") = [_]GDTEntry{
    GDTEntry{
        .limit1 = 0,
        .base1 = 0,
        .base2 = 0,
        .access = 0,
        .limit2 = 0,
        .flags = 0,
        .base3 = 0,
    },
    GDTEntry{
        .limit1 = 0xFFFF,
        .base1 = 0x0,
        .base2 = 0x0,
        .access = 0b10011010,
        .limit2 = 0xF,
        .flags = 0b1010,
        .base3 = 0x0,
    },
    GDTEntry{
        .limit1 = 0xFFFF,
        .base1 = 0x0,
        .base2 = 0x0,
        .access = 0b10010010,
        .limit2 = 0xF,
        .flags = 0b1100,
        .base3 = 0x0,
    },
};

// TODO: Set granularity

/// Struct defining a GDT entry. GDTs are weird so variables are set with functions to abstract it, though they should never
/// be modified after the first stages of booting where they're defined with init() since I'm using paging.
const GDTEntry = packed struct(u64) {
    // TODO: should these be reversed?
    limit1: u16,
    base1: u16,
    base2: u8,
    access: u8,
    limit2: u4,
    flags: u4,
    base3: u8,

    /// Initialize the GDT entry at the given address. Abstract away the weirdness
    pub inline fn init(self: *GDTEntry, limit: u20, base: u32, access: u8, flags: u4) linksection(".boottext") void {
        // BUG: Maybe truncate is linked with the 64 bit stuff and calling it isn't working
        comptime {
            self.limit1 = @truncate((limit & 0x0FFFF));
            self.limit2 = @truncate((limit & 0xF0000) >> 16);
            self.base1 = @truncate((base & 0x0000FFFF));
            self.base2 = @truncate((base & 0x00FF0000) >> 16);
            self.base3 = @truncate((base & 0xFF000000) >> 24);
            self.access = access;
            self.flags = flags;
        }
    }

    pub fn print(self: *GDTEntry) linksection(".boottext") void {
        Console.print("Limit: 0x{X}{X}\n", .{ self.limit2, self.limit1 });
        Console.print("Base: 0x{X}{X}{X}\n", .{ self.base3, self.base2, self.base1 });
    }
};

/// Global storing GDT information. Processor pointed at this to load the GDT
const GDTRt = packed struct {
    limit: u16,
    padding: u32,
    base: *const GDTEntry,
};

var gdtr: GDTRt linksection(".bootdata") = GDTRt{
    .limit = 3 * @sizeOf(GDTEntry),
    .padding = 0,
    .base = &GDT[0],
};

/// Tells the processor where the GDT is
inline fn loadGDT() linksection(".boottext") void {
    asm volatile ("lgdt %[gdtr]"
        :
        : [gdtr] "m" (&gdtr),
    );
}

/// sgdt gets the data in the GDTR
fn storeGDT() linksection(".boottext") GDTRt {
    var data = GDTRt{ .limit = 0, .base = 0 };
    asm volatile ("sgdt %[data]"
        : [data] "=m" (data),
    );
    return data;
}

/// Functin the kernel calls into to initialize the GDT
/// This should NEVER be called without interrupts being disabled!
/// Inline in case returning screws things up when I need to jump to 64 bit
/// init() is ignored because it depends on @truncate(), which errors out because it's linked with the 64 bit stuff
pub inline fn init() linksection(".boottext") void {
    arch.disableInterrupts();
    loadGDT();
}
