const native_endian = @import("builtin").target.cpu.arch.endian();
const arch = @import("arch.zig");
const Console = arch.Console;

/// Base address of the GDT table
var GDT: [6]GDTEntry linksection(".bootdata") = undefined;

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
    pub fn init(self: *GDTEntry, limit: u20, base: u32, access: u8, flags: u4) linksection(".boottext") void {
        self.limit1 = @truncate((limit & 0x0FFFF));
        self.limit2 = @truncate((limit & 0xF0000) >> 16);
        self.base1 = @truncate((base & 0x0000FFFF));
        self.base2 = @truncate((base & 0x00FF0000) >> 16);
        self.base3 = @truncate((base & 0xFF000000) >> 24);
        self.access = access;
        self.flags = flags;
    }

    pub fn print(self: *GDTEntry) linksection(".boottext") void {
        Console.print("Limit: 0x{X}{X}\n", .{ self.limit2, self.limit1 });
        Console.print("Base: 0x{X}{X}{X}\n", .{ self.base3, self.base2, self.base1 });
    }
};

/// Global storing GDT information. Processor pointed at this to load the GDT
const GDTRt = packed struct {
    limit: u16,
    base: u64,
};

var gdtr: GDTRt linksection(".bootdata") = undefined;

/// Tells the processor where the GDT is
/// base: pointer to GDT[0], limit: number of entries
fn loadGDT(base: *GDTEntry, limit: u8) linksection(".boottext") void {
    // LGDT wants a pointer to a 6 byte region of memory with the base and length of the gdt
    gdtr = .{
        .limit = limit * @sizeOf(GDTEntry),
        .base = @intFromPtr(base),
    };
    asm volatile ("lgdt (%[gdtr])"
        :
        : [gdtr] "{eax}" (&gdtr),
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

pub const NULL_SEGMENT = 0x0;
pub const CODE_SEGMENT = 0x1;
pub const DATA_SEGMENT = 0x2;

/// Functin the kernel calls into to initialize the GDT
/// This should NEVER be called without interrupts being disabled!
pub fn init() linksection(".boottext") void {
    arch.disableInterrupts();
    GDT[NULL_SEGMENT].init(0x0, 0x0, 0x0, 0x0);
    // NOTE: If there are weird errors this might be wrong
    GDT[CODE_SEGMENT].init(0xFFFFF, 0x0, 0b10011010, 0b1010);
    GDT[DATA_SEGMENT].init(0xFFFFF, 0x0, 0b10010010, 0b1100);
    loadGDT(&GDT[0], 6);
}
