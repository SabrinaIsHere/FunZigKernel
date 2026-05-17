//! https://wiki.osdev.org/MADT
//! https://uefi.org/specs/ACPI/6.5/05_ACPI_Software_Programming_Model.html#multiple-apic-description-table-madt
//! TODO: This file should be APIC.zig, or everything should be lowercase
//! TODO: Remap IRQs

const std = @import("std");
const arch = @import("arch.zig");
const main = arch.main;
const kallocator = arch.kallocator;
const acpi = arch.ACPI;
const Console = arch.Console;
const print = Console.print;
const Cpuid = arch.Cpuid;
const Paging = arch.Paging;

const APICError = error{
    InvalidIndex,
};

/// Standard ISA IRQs. Use assuming there are no remappings, will be translated transparently in functions
const IRQs = enum(u4) {
    pit,
    keyboard,
    cascade,
    com2,
    com1,
    lpt2,
    floppy,
    lpt1,
    cmos,
    free1,
    free2,
    free3,
    ps2_mouse,
    coprocessor,
    primary_ata,
    secondary_ata,
};

/// Redirection entry delivery modes
const DeliveryMode = enum(u3) {
    normal,
    low_priority,
    system_management,
    reserved1,
    nmi,
    init,
    reserved2,
    external,
};

/// Used for programming the IOApic
const RedirectionEntry = packed struct(u64) {
    vector: u8,
    delivery_mode: DeliveryMode,
    /// 0 is physical, 1 is logical
    destination_mode: u1,
    /// Read only. Set when the interrupt is about to be sent
    apic_busy: u1,
    /// If 0 high is active, if 1 low is active
    polarity: u1,
    /// Level triggered interrupts, 1 if lapic has received, 0 if sent EOI. Read only
    remote_irr: u1,
    /// 0 is edge sensitive, 1 is level sensitive
    trigger_mode: u1,
    /// Mask interrupt (obviously)
    int_mask: bool,
    reserved: u39,
    destination: u8,
};

/// Encapsulates interactions with a specific ioapic
/// NOTE: This is also doable with a packed struct but I'd need a lot of offset bc of how high the data register is,
/// plus I want to store other data about the ioapic in this struct
const IOApic = struct {
    /// IOApic's id
    id: u8,
    /// Address of this ioapic
    addr: [*]volatile u32,
    /// Global interrupt base
    int_base: u32,
    /// How many IRQs can this handle
    max_redirection_entries: u8 = 0,

    /// Initializes derived data (anything with a default value)
    /// Different from my normal pattern to make it fit into the MADT parsing code more cleanly
    pub fn init(id: u8, addr: usize, int_base: u32) IOApic {
        var self = IOApic{
            .id = id,
            .addr = @ptrFromInt(addr),
            .int_base = int_base,
        };
        // Encoded in bits 16-23
        self.max_redirection_entries = @truncate(self.read(1) >> 16);
        return self;
    }

    /// Read from a register
    pub fn read(self: *IOApic, reg: u32) u32 {
        self.addr[0] = (reg & 0xFF);
        return self.addr[4];
    }

    /// Write to a register
    pub fn write(self: *IOApic, reg: u32, val: u32) void {
        self.addr[0] = (reg & 0xFF);
        self.addr[4] = val;
    }

    /// Dumps all the redirection entries into a list
    pub fn getRedirectionEntries(self: *IOApic, al: std.mem.Allocator) ![]RedirectionEntry {
        var list = try std.ArrayList(RedirectionEntry).initCapacity(al, self.max_redirection_entries);
        var i: u32 = 0;
        while (i < self.max_redirection_entries) {
            const high_val: u64 = self.read(@truncate(0x10 + i));
            const low_val: u64 = self.read(@truncate(0x11 + i));
            try list.append(al, @bitCast(high_val << 32 | low_val));
            i += 2;
        }
        return list.items;
    }

    /// Set a redirection entry. Index is the index into the entries, not memory
    pub fn setRedirectionEntry(self: *IOApic, index: u32, entry: RedirectionEntry) APICError!void {
        if (index > self.max_redirection_entries) return APICError.InvalidIndex;
        self.write(0x10 + index, @truncate(@as(u64, @bitCast(entry)) >> 32));
        self.write(0x11 + index, @truncate(@as(u64, @bitCast(entry))));
    }

    /// Mask or unmask an IRQ
    pub fn maskIRQ(self: *IOApic, masked: bool, index: u32) APICError!void {
        const entry_high: u64 = self.read(@truncate(0x10 + index));
        const entry_low: u64 = self.read(@truncate(0x11 + index));
        var entry: RedirectionEntry = @bitCast(entry_high << 32 | entry_low);
        entry.int_mask = masked;
        try self.setRedirectionEntry(index, entry);
    }

    /// Set a range of IRQs' masked state
    pub fn maskRange(self: *IOApic, masked: bool, start: u32, end: u32) APICError!void {
        for (start..end) |i| try self.maskIRQ(masked, @intCast(i));
    }
};

/// Aid in translating IRQs in the case of overrides indicated by the MADT
/// NOTE: I'm not actually clear that this is necessary? Reevaluate when less hungry
const Override = struct {
    standard: IRQs,
    new: u8,
};

/// List of ioapics gathered from the MADT. Defined in init()
var io_apics: []IOApic = undefined;
var overrides: []Override = undefined;

/// Initialize the APIC(s)
pub fn init() void {
    // TODO: Sanity check that lapic is configure how I expect
    defer print("APICs configured\n", .{});
    // Get data, error checking
    const al = main.al orelse @panic("apic.init() called before al is initialized");
    if (!Cpuid.cpu_info.apic) @panic("Apic not available.\n");
    const madt = acpi.parseMADT(al) catch @panic("Couldn't get MADT");
    defer al.free(madt);
    // Parse MADT
    var tmp_io_apics = std.ArrayList(IOApic).initCapacity(al, 10) catch @panic("apic.init(): out of memory");
    for (madt) |madte| {
        const madte_data = madte.getData(u8);
        print("{any}\n", .{madte});
        switch (madte.type) {
            .io_apic => {
                const addr: u32 = @bitCast(madte_data[2..6].*);
                Paging.map(addr, arch.physicalToVirtual(addr));
                tmp_io_apics.append(al, IOApic.init(
                    madte_data[0],
                    arch.physicalToVirtual(addr),
                    @bitCast(madte_data[6..10].*),
                )) catch @panic("apic.init(): out of memory");
            },
            .local_apic => {
                //print("Local: {any}\n", .{madte_data});
            },
            // NOTE: Limine interacts with the interrupt controllers so I'll get around to parsing this if it seems necessary
            .io_apic_int_src_override => {
                print("Override: {any}\n", .{madte_data});
            },
            else => {},
        }
    }
    io_apics = tmp_io_apics.items;
    print("{any}\n", .{io_apics});
    // BUG: APIC read/write may not be doing anything
    io_apics[0].maskRange(false, 0, 12) catch unreachable;
    print("{any}\n", .{io_apics[0].getRedirectionEntries(al) catch unreachable});
}

/// This isn't making sense to me so I'm gonna deal with it later
fn translateIRQ(irq: IRQs) u8 {
    _ = irq;
}

/// Finds and replaces the relevent redirection entry
pub fn setIRQ(vector: u32, entry: RedirectionEntry) void {
    for (io_apics) |ioapic| {
        if (vector >= ioapic.int_base) {
            ioapic.setRedirectionEntry(vector - ioapic.int_base, entry);
        }
    }
}
