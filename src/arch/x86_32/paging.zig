const arch = @import("arch.zig");

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

    pub fn init(self: *PML4E, addr: u36, rw: bool, pwt: u1, pcd: u1) linksection(".boottext") void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = addr;
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
    pd_phys_addr: u36 = 0,
    reserved2: u15 = 0,
    xd: bool = false,

    pub fn init(self: *PDPTE, pd_phys_addr: u36, pwt: u1, pcd: u1) linksection(".boottext") void {
        self.present = true;
        self.pwt = pwt;
        self.pcd = pcd;
        self.pd_phys_addr = pd_phys_addr;
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
    // TODO: Figure out what EFER.NXE is
    xd: bool = false,

    pub fn init(
        self: *PDE,
        addr: u36,
        rw: bool,
        pwt: u1,
        pcd: u1,
    ) linksection(".boottext") void {
        self.present = true;
        self.addr = addr;
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
        rw: bool,
        pwt: u1,
        pcd: u1,
        global: bool,
        addr: u36,
    ) linksection(".boottext") void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.global = global;
        self.addr = addr;
    }
};

/// Highest order paging structure, loaded into the processor
var PML4: [1]PML4E align(0x1000) linksection(".bootdata") = [_]PML4E{.{}} ** 1;
/// Second order paging structure
var PDPT: [1]PDPTE align(0x1000) linksection(".bootdata") = [_]PDPTE{.{}} ** 1;
/// Third order paging structure
var PDT: [1]PDE align(0x1000) linksection(".bootdata") = [_]PDE{.{}} ** 1;
/// Fourth order paging structure
var PT: [512]PTE align(0x1000) linksection(".bootdata") = [_]PTE{.{}} ** 512;

/// Initialize and enable paging
/// Maps the first 2 MiB
pub fn init() linksection(".boottext") void {
    for (0..PT.len) |i| {
        PT[i].init(true, 1, 1, false, i * 4096);
    }
    PDT[0].init(@intFromPtr(&PT), true, 1, 1);
    PDPT[0].init(@intFromPtr(&PDT), 1, 1);
    PML4[0].init(@intFromPtr(&PDPT), true, 1, 1);
    arch.setPML4(&PML4[0]);
}
