const arch = @import("arch.zig");
const Console = arch.Console;
const print = Console.print;
const kallocator = @import("../../memory/kallocator.zig");

// TODO: Parse and copy limine paging structure

const PagingError = error{
    InvalidPhysicalAddress,
};

/// References a PDPT
/// Handles mapping logic
/// TODO: Allocate PT when needed?
pub const PML4E = packed struct(u64) {
    present: bool = true,
    rw: bool = true,
    us: u1 = 1,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved1: u6 = 0,
    addr: u48 = 0,
    reserved2: u3 = 0,
    xd: u1 = 0,

    pub fn init(self: *PML4E, addr: usize, rw: bool, pwt: u1, pcd: u1) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
    }

    pub fn getPTE(self: *PML4E, virt_addr: usize) *PTE {
        const pdptindex: u9 = (virt_addr >> 30) & 0x1FF;
        const pdindex: u9 = (virt_addr >> 21) & 0x1FF;
        const ptindex: u9 = (virt_addr >> 12) & 0x03FF;
        const pdpt: *[512]PDPTE = @ptrFromInt(self.addr);
        const pd: *[512]PDE = @ptrFromInt(pdpt[pdptindex]);
        const pt: *[512]PTE = @ptrFromInt(pd[pdindex]);
        return pt[ptindex];
    }

    pub fn map(self: *PML4E, phys_addr: usize, virt_addr: usize) void {
        const pte: *PTE = self.getPTE(virt_addr);
        pte.init(phys_addr, true, 1, 1, 1);
    }

    pub fn unmap(self: *PML4E, virt_addr: usize) void {
        const pte: *PTE = self.getPTE(virt_addr);
        pte.present = false;
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
    addr: u48 = 0,
    reserved2: u3 = 0,
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
    addr: u48 = 0,
    reserved: u3 = 0,
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
    addr: u48 = 0,
    reserved: u3 = 0,
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
var pml4: *PML4E = undefined;

// TODO: When there's a functional allocator this should stop being static

/// Initialize and enable paging
/// Maps the first 2 MiB
pub fn init() void {
    defer Console.print("Paging enabled\n", .{});
    pml4 = allocatePageTable() catch @panic("Page table allocation error");
    //arch.setPML4(&pml4[0]);
}

/// Runs a couple tests to make sure everything is in order before we attempt to load cr4
/// Only for use when debugging
fn runtimeTests() PagingError!void {
    // Check that the physical address is translating
    // NOTE: This isn't doing anything, figure out how to verify a physical address
    const pml4_physical: usize = arch.virtualToPhysical(@intFromPtr(&pml4[0]));
    Console.print("PML4 Physical: 0x{X}\n", .{pml4_physical});
    const pml4_virtual: usize = arch.physicalToVirtual(pml4_physical);
    Console.print("PML4 Virtual: 0x{X}\n", .{pml4_virtual});
    if (pml4_virtual != @intFromPtr(&pml4[0])) return PagingError.InvalidPhysicalAddress;
}

pub fn allocatePageTable() kallocator.MemError!*PML4E {
    const pt: *[512][512][512]PTE = @ptrCast(try kallocator.get(PTE, 512 * 512 * 512));
    const pd: *[512][512]PDE = @ptrCast(try kallocator.get(PDE, 512 * 512));
    for (0..512) |i| {
        for (0..512) |j| {
            pd[i][j].init(@intFromPtr(&pt[i][j][0]), true, 1, 1);
        }
    }
    const pdpt: *[512]PDPTE = @ptrCast(try kallocator.get(PDPTE, 512));
    for (0..512) |i| {
        pdpt[i].init(@intFromPtr(&pd[i][0]), 1, 1);
    }
    const retval: *PML4E = @ptrCast(try kallocator.get(PML4E, 1));
    pml4.init(@intFromPtr(&pdpt), true, 1, 1);
    return retval;
}

pub fn map(phys: usize, virt: usize) void {
    pml4.map(phys, virt);
}

pub fn unmap(virt: usize) void {
    pml4.unmap(virt);
}
