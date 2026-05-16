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

/// Encapsulates interactions with a specific ioapic
/// NOTE: This is also doable with a packed struct but I'd need a lot of offset bc of how high the data register is,
/// plus I want to store other data about the ioapic in this struct
const IOApic = struct {
    /// IOApic's id
    id: u8,
    /// Address of this ioapic
    addr: [*]align(1) u32,
    /// Global interrupt base
    int_base: u32,

    /// Intended to be called when parsing the MADT
    pub fn init(self: *IOApic, id: u8, addr: usize, int_base: u32) void {
        self.id = id;
        self.addr = @ptrFromInt(addr);
        self.int_base = int_base;
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
};

/// List of ioapics gathered from the MADT. Defined in init()
var io_apics: []IOApic = undefined;

/// Initialize the APIC(s)
/// TODO: Look into reading MSR instead of going through APIC?
pub fn init() void {
    // Get data, error checking
    const al = main.al orelse @panic("apic.init() called before al is initialized");
    if (!Cpuid.cpu_info.apic) @panic("Apic not available.\n");
    const madt = acpi.parseMADT(al) catch @panic("Couldn't get MADT");
    // Parse MADT
    var tmp_io_apics = std.ArrayList(IOApic).initCapacity(al, 10) catch @panic("apic.init(): out of memory");
    for (madt) |madte| {
        const madte_data = madte.getData(u8);
        print("{any}\n", .{madte});
        switch (madte.type) {
            .io_apic => {
                const addr: u32 = @bitCast(madte_data[2..6].*);
                Paging.map(addr, arch.physicalToVirtual(addr));
                tmp_io_apics.append(al, .{
                    .id = madte_data[0],
                    .addr = @ptrFromInt(arch.physicalToVirtual(addr)),
                    .int_base = @bitCast(madte_data[6..10].*),
                }) catch @panic("apic.init(): out of memory");
            },
            .local_apic => {
                //print("Local: {any}\n", .{madte_data});
            },
            // NOTE: Limine interacts with the interrupt controllers so I'll get around to parsing this if it seems necessary
            .io_apic_int_src_override => {
                //print("Override: {any}\n", .{madte_data});
            },
            else => {},
        }
    }
    io_apics = tmp_io_apics.items;
    print("{any}\n", .{io_apics});
}
