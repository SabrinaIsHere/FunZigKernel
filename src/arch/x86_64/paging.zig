const arch = @import("arch.zig");
const Console = arch.Console;

// TODO: Parse and copy limine paging structure

const PagingError = error{
    InvalidPhysicalAddress,
};

/// References a PDPT
/// Public so arch can be passed a pointer to it
pub const PML4E = packed struct(u64) {
    present: bool = true,
    rw: bool = true,
    us: u1 = 1,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved1: u6 = 0,
    addr: u36 = 0,
    reserved2: u15 = 0,
    xd: u1 = 0,

    pub fn init(self: *PML4E, addr: usize, rw: bool, pwt: u1, pcd: u1) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
    }
};

/// References a page directory
const PDPTE = packed struct(u64) {
    present: bool = false,
    rw: bool = true,
    us: bool = true,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved: u6 = 0,
    addr: u36 = 0,
    reserved2: u15 = 0,
    xd: bool = false,

    pub fn init(self: *PDPTE, addr: usize, pwt: u1, pcd: u1) void {
        self.present = true;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
    }
};

/// References a page table
const PDE = packed struct(u64) {
    present: bool = false,
    rw: bool = false,
    us: u1 = 0,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    ignored1: u1 = 0,
    ps: u1 = 0,
    ignored2: u4 = 0,
    addr: u36 = 0,
    reserved: u15 = 0,
    xd: bool = false,

    pub fn init(
        self: *PDE,
        addr: usize,
        rw: bool,
        pwt: u1,
        pcd: u1,
    ) void {
        self.present = true;
        self.addr = @truncate(addr);
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
    }
};

/// Defines a 4 KiB page
const PTE = packed struct(u64) {
    present: bool = false,
    rw: bool = false,
    us: u1 = 0,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    dirty: bool = false,
    pat: u1 = 0,
    global: bool = false,
    ignored1: u3 = 0,
    addr: u36 = 0,
    reserved: u15 = 0,
    xd: bool = false,

    pub fn init(
        self: *PTE,
        addr: usize,
        rw: bool,
        pwt: u1,
        pcd: u1,
        global: bool,
    ) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.global = global;
        self.addr = @truncate(addr);
    }
};

/// Pointer to paging structures setup by limine. Virtual address
var limine_pml4: *PML4E = undefined;

// TODO: When there's a functional allocator this should stop being static

/// Highest order paging structure, loaded into the processor
var PML4: [1]PML4E align(0x1000) = [_]PML4E{.{}} ** 1;
/// Second order paging structure
var PDPT: [512]PDPTE align(0x1000) = [_]PDPTE{.{}} ** 1;
/// Third order paging structure
var PDT: [512][512]PDE align(0x1000) = [_]PDE{.{}} ** 1;
/// Fourth order paging structure
var PT: [512]PTE align(0x1000) = [_]PTE{.{}} ** 512;

/// Initialize and enable paging
/// Maps the first 2 MiB
pub fn init() void {
    defer Console.print("Paging enabled\n", .{});
    //limine_pml4 = arch.getPML4(); // This isn't working
    //Console.print("Limine PML4: {any}\n", .{limine_pml4});
    for (0..PT.len) |i| {
        PT[i].init(i * 4096, true, 1, 1, false);
    }
    PDT[0].init(@intFromPtr(&PT), true, 1, 1);
    PDPT[0].init(@intFromPtr(&PDT), 1, 1);
    PML4[0].init(@intFromPtr(&PDPT), true, 1, 1);
    //runtimeTests() catch arch.k_panic("Paging error\n"); // Not helping rn
    arch.setPML4(&PML4[0]);
}

/// Runs a couple tests to make sure everything is in order before we attempt to load cr4
/// Only for use when debugging
fn runtimeTests() PagingError!void {
    // Check that the physical address is translating
    // NOTE: This isn't doing anything, figure out how to verify a physical address
    const pml4_physical: usize = arch.virtualToPhysical(@intFromPtr(&PML4[0]));
    Console.print("PML4 Physical: 0x{X}\n", .{pml4_physical});
    const pml4_virtual: usize = arch.physicalToVirtual(pml4_physical);
    Console.print("PML4 Virtual: 0x{X}\n", .{pml4_virtual});
    if (pml4_virtual != @intFromPtr(&PML4[0])) return PagingError.InvalidPhysicalAddress;
}

pub fn map(phys: usize, virt: usize) void {
    _ = phys;
    _ = virt;
}

pub fn unmap(virt: usize) void {
    _ = virt;
}
