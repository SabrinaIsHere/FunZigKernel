//! https://wiki.osdev.org/MADT
//! https://uefi.org/specs/ACPI/6.5/05_ACPI_Software_Programming_Model.html#multiple-apic-description-table-madt

// NOTE: This is gonna have to wait for a bunch of uefi/grub parsing stuff unfortunately
// NOTE: Get the rsdp from grub? idk man

const arch = @import("arch.zig");
const Console = arch.Console;
const Cpuid = @import("cpuid.zig");

// TODO: Parse MADT
// TODO: Remap IRQs

// NOTE: Walk the MADT, put all of the entries in a list of structs defining them with types and pointers

/// Header before the hardware describing entries in the MADT
const MADTHeader = packed struct {
    signature_apic: u32,
    length: u32,
    revision: u8,
    checksum: u8,
    oemid: u48,
    oem_table_id: u64,
    oem_revision: u32,
    creator_id: u32,
    creator_revision: u32,
    local_apic_address: u32,
    pcat_compat: u1,
    flags: u31,
    first_entry: MADTEntryDescriptor,
};

const EntryType = enum(u8) {
    LocalApic,
    IOApic,
    IOApicInterruptSourceOverride,
    IOApicNMISource,
    LocalApicNMIs,
    LocalApicAddressOverride,
    ProcessorLocalx2Apic,
};

/// Describes MADT entries in a way that's easier to interact with, given that they're variable length
const MADTEntryDescriptor = packed struct {
    type: EntryType,
    length: u8,
};

/// Buffer of madt entry descriptors for later parsing
/// I make the assumption that there won't be more than 256 entries but I'm not seeing any specifics about general length
var madt_entries: [256]MADTEntryDescriptor = undefined;

/// Initialize the APIC(s)
pub fn init() void {
    if (!Cpuid.cpu_info.apic) arch.k_panic("Apic not available.\n", .{});
    // Don't forget to verify the checksum
}

/// Walks the MADT and populates madt_entries, which will be used for further processing
fn walkMADT() void {}
