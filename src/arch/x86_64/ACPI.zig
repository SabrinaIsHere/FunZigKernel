//! https://wiki.osdev.org/RSDT

const std = @import("std");
const arch = @import("arch.zig");
const main = arch.main;
const Console = main.Console;
const print = Console.print;

const AcpiError = error{
    InvalidXSDP,
    InvalidXSDT,
    InvalidMADT,
};

/// RSDP header, data structure pointed to by limine feature
const RSDPHeader = extern struct {
    signature: [8]u8,
    checksum: u8,
    oemid: [6]u8,
    revision: u8,
    rsdt_address: u32,

    pub fn sum(self: *RSDPHeader) usize {
        var sum1: u8 = 0;
        for (self.signature) |c| sum1 +%= c;
        sum1 +%= self.checksum;
        for (self.oemid) |c| sum1 +%= c;
        sum1 +%= self.revision;
        inline for (0..4) |i| sum1 +%= @as(u8, @truncate((self.rsdt_address & (0xFF << (i * 8))) >> (i * 8)));
        return sum1;
    }
};
/// Separated so either can be used
const XSDPHeader = extern struct {
    signature: [8]u8,
    checksum: u8,
    oemid: [6]u8,
    revision: u8,
    rsdt_address: u32,
    length: u32,
    xsdt_address: u64,
    extended_checksum: u8,
    reserved: [3]u8,

    pub fn sum(self: *XSDPHeader) usize {
        var sum1: u8 = 0;
        const bytes: [*]u8 = @ptrCast(self);
        for (0..self.length) |i| sum1 +%= bytes[i];
        return sum1;
    }
};

/// Common acpi table header
const SDTHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oemid: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,

    pub fn sum(self: *SDTHeader) u8 {
        var sum1: u8 = 0;
        // Iterate through and add every byte
        const bytes: [*]u8 = @ptrCast(self);
        for (0..self.length) |i| sum1 +%= bytes[i];
        return sum1;
    }

    pub fn getData(self: *SDTHeader, T: type) align(1) []align(1) T {
        const num: u32 = (self.length - @sizeOf(SDTHeader)) / @sizeOf(T);
        const arr: [*]align(1) T = @ptrFromInt(@intFromPtr(self) + @sizeOf(SDTHeader));
        return arr[0..num];
    }
};

const MADTEType = enum(u8) {
    local_apic,
    io_apic,
    io_apic_int_src_override,
    apic_nmi_src,
    local_apic_nmi,
    local_apic_addr_override,
    local_x2apic,
};

/// Standard MADTE header and accompanying data retrieval function
const MADTEHeader = packed struct {
    type: MADTEType,
    length: u8,

    /// Returns data in specified type. Does not include standard header
    pub fn getData(self: *MADTEHeader, T: type) align(1) []align(1) T {
        const arr: [*]u8 = @ptrCast(self);
        // Don't include standard header
        return @ptrCast(arr[@sizeOf(@This())..self.length]);
    }
};

/// Can be rsdt or xsdt
var xsdt: *SDTHeader = undefined;
var madt: ?*SDTHeader = null;

/// Parses acpi tables. Errors out if an xsdp isn't passed
pub fn init() AcpiError!void {
    const response = main.rsdp.response.?;
    // Zig is being a huge pain in the ass about alignment so this is what I'm forced to do
    const xsdp_unaligned: [*]u8 = @ptrFromInt(arch.physicalToVirtual(response.address));
    var xsdp_buffer: [40]u8 = undefined;
    @memcpy(xsdp_buffer[0..36], xsdp_unaligned);
    var xsdp: XSDPHeader = @bitCast(xsdp_buffer);
    if (xsdp.sum() != 0) return AcpiError.InvalidXSDP;
    xsdt = @ptrFromInt(arch.physicalToVirtual(xsdp.xsdt_address));
    if (!std.mem.eql(u8, &xsdt.signature, "XSDT") or xsdt.sum() != 0) return AcpiError.InvalidXSDT;
    // Table is valid, now to get tables I actually want
    const acpi_tables = xsdt.getData(usize);
    for (acpi_tables) |table_phys| {
        const table: *SDTHeader = @ptrFromInt(arch.physicalToVirtual(table_phys));
        if (std.mem.eql(u8, &table.signature, "APIC")) {
            madt = table;
        }
    }
}

/// Walk the madt and put entries in a more convenient format to work with
pub fn parseMADT(al: std.mem.Allocator) ![]*MADTEHeader {
    // Start at eight to skip the madt header
    const madt_data: []u8 = madt.?.getData(u8)[8..];
    var retval = try std.ArrayList(*MADTEHeader).initCapacity(al, 30);
    var num: u8 = 0;
    var i: usize = 0;
    while (i < madt_data.len and num < 30) {
        const curr_entry: *MADTEHeader = @ptrCast(@alignCast(&madt_data[i]));
        try retval.append(al, curr_entry);
        num += 1;
        i += curr_entry.length;
    }
    return retval.items;
}
