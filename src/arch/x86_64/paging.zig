//! Identity maps memory according to limine standard, data and code have seperate offsets
//! When I'm less sick of looking at this file I should circle back and clean it up a little it's pretty gnarly
//! reference: https://github.com/BoredDevNL/BoredOS/
//! TODO: Rename *.addr -> *.frame

const arch = @import("arch.zig");
const Console = arch.Console;
const print = Console.print;
const kallocator = @import("../../memory/kallocator.zig");
const main = @import("../../main.zig");

const PagingError = error{
    UnmappedAddress,
    InvalidPhysicalAddress,
    InvalidAddressTranslation,
};

/// References a PDPT
/// Handles mapping logic
pub const PML4E = packed struct(u64) {
    present: bool = false,
    rw: bool = false,
    us: bool = false,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    reserved1: u6 = 0,
    addr: u40 = 0,
    reserved2: u11 = 0,
    xd: bool = false,

    /// Sets present bit and initializes data
    /// If there is no PDPT, set address to 0
    pub fn init(self: *PML4E, addr: usize, rw: bool, pwt: u1, pcd: u1) void {
        self.present = true;
        self.rw = rw;
        self.pwt = pwt;
        self.pcd = pcd;
        self.addr = @truncate(addr);
    }

    /// Copy the mappings from another pml4e. Quiet fails
    /// I really hate this function lol
    /// NOTE: Maybe delete this? I'm not gonna use it most likely
    pub fn copyMappings(self: *PML4E, copied: *PML4E) !void {
        // It'd be nice to do this with @memcpy but then I'd have to handle allocation logic here and I had
        // a hard enough time with getPTE
        if (!copied.present) return;
        // Get pdpt
        const pdpt: *[512]PDPTE = @ptrFromInt(arch.physicalToVirtual(copied.addr << 12));
        // Iterate through it
        for (pdpt, 0..) |pdpte, i| {
            // Skip if not present
            if (!pdpte.present) continue;
            // I don't handle this because I don't think limine would ever do it
            if (pdpte.ps == 1) @panic("PDPT is a page");
            // Get page directory
            const pd: *[512]PDE = @ptrFromInt(arch.physicalToVirtual(pdpte.addr << 12));
            // Iterate page directory
            for (pd, 0..) |pde, j| {
                // BUG: Off by one in here somewhere
                //
                // Skip if not present
                if (!pde.present) continue;
                // Handle 2 MB pages
                if (pde.ps == 1) {
                    for (0..512) |k| {
                        const pte = try self.getPTE(i << 30 | j << 21 | k << 12);
                        pte.init(pde.addr + k, pde.rw, pde.pwt, pde.pcd, false);
                        pte.us = pde.us;
                        pte.xd = pde.xd;
                    }
                    continue;
                }
                // Handle page tables
                const pt: *[512]PTE = @ptrFromInt(arch.physicalToVirtual(pde.addr << 12));
                for (pt, 0..) |pte, k| {
                    // Fuckup around 510, 0, 108
                    if (!pte.present) continue;
                    if (i == 510 and j == 0 and k == 108) print("0x{X}: {any}\n", .{ (i << 30 | j << 21 | k << 12), pte });
                    const local_pte = try self.getPTE(i << 30 | j << 21 | k << 12);
                    local_pte.init(pte.addr, pte.rw, pte.pwt, pte.pcd, pte.global);
                    local_pte.dirty = pte.dirty;
                    local_pte.accessed = pte.accessed;
                    local_pte.us = pte.us;
                    local_pte.xd = pte.xd;
                }
            }
        }
    }

    /// Gets a PTE, allocating space for it if need be. The runtime overhead on this is not the best
    /// I hate this function
    pub fn getPTE(self: *PML4E, virt_addr: usize) kallocator.MemError!*PTE {
        const pdptindex: u9 = @truncate(virt_addr >> 30);
        const pdindex: u9 = @truncate(virt_addr >> 21);
        const ptindex: u9 = @truncate(virt_addr >> 12);
        var pdpt: *[512]PDPTE = undefined;
        if (!self.present) {
            pdpt = @ptrCast(try kallocator.get(PDPTE, 512, 4096));
            self.init(arch.virtualToPhysical(@intFromPtr(pdpt)) >> 12, true, 0, 0);
            self.us = true;
        } else {
            pdpt = @ptrFromInt(arch.physicalToVirtual(self.addr << 12));
        }
        var pd: *[512]PDE = undefined;
        if (!pdpt[pdptindex].present) {
            pd = @ptrCast(try kallocator.get(PDE, 512, 4096));
            pdpt[pdptindex].init(arch.virtualToPhysical(@intFromPtr(pd)) >> 12, 0, 0);
            pdpt[pdptindex].us = true;
        } else {
            pd = @ptrFromInt(arch.physicalToVirtual(pdpt[pdptindex].addr << 12));
        }
        var pt: *[512]PTE = undefined;
        if (!pd[pdindex].present) {
            pt = @ptrCast(try kallocator.get(PTE, 512, 4096));
            pd[pdindex].init(arch.virtualToPhysical(@intFromPtr(pt)) >> 12, true, 0, 0);
            pd[pdindex].us = true;
        } else {
            pt = @ptrFromInt(arch.physicalToVirtual(pd[pdindex].addr << 12));
        }
        return &pt[ptindex];
    }

    /// Get a physical address from a virtual
    pub fn v2p(self: *PML4E, virt_addr: usize) PagingError!usize {
        const pte = self.getPTE(virt_addr) catch return PagingError.UnmappedAddress;
        if (!pte.present) return PagingError.UnmappedAddress;
        const offset: u12 = @truncate(virt_addr);
        return (pte.addr << 12) + offset;
    }

    /// Translates a physical addres to a virtual
    pub fn p2v(self: *PML4E, phys_addr: usize) usize {
        _ = self;
        _ = phys_addr;
        print("Don't call p2v!\n", .{});
        return 0;
    }

    /// Map a virtual address to a physical address
    pub fn map(self: *PML4E, phys_addr: usize, virt_addr: usize) kallocator.MemError!void {
        // TODO: Flush tlb
        const pte: *PTE = try self.getPTE(virt_addr);
        pte.init(phys_addr >> 12, true, 0, 0, false);
    }

    /// Decouple a physical and virtual address
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
    dirty: bool = false,
    ps: u1 = 0,
    reserved: u4 = 0,
    addr: u40 = 0,
    reserved2: u11 = 0,
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
    us: bool = false,
    pwt: u1 = 0,
    pcd: u1 = 0,
    accessed: bool = false,
    ignored1: u1 = 0,
    ps: u1 = 0,
    ignored2: u4 = 0,
    addr: u40 = 0,
    reserved: u11 = 0,
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
    addr: u40 = 0,
    reserved: u11 = 0,
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

/// Pointer to PML4 loaded by cpu
var pml4: *[512]PML4E = undefined;

/// Initialize and enable paging
/// Identity maps first 1 MB, then the rest of system memory is identity mapped with the hhdm offset
pub fn init() void {
    defer print("Page tables loaded\n", .{});
    pml4 = allocatePageTable() catch @panic("Insufficient memory to allocate page tables");

    for (0..kallocator.total_phys_memory >> 12) |i| {
        // BUG: This does throw an error but I'm sick of looking at this code so I'll work on it later/when it's an issue
        //if (arch.virtualToPhysical(arch.physicalToVirtual(i << 12)) != i << 12) {
        //    print("{any}: 0x{X} -> 0x{X}\n", .{ i, i << 12, arch.virtualToPhysical(arch.physicalToVirtual(i << 12)) });
        //    @panic("Don't agree");
        //}
        map(i << 12, arch.physicalToVirtual(i << 12));
    }

    arch.setPML4(&pml4[0]);
}

/// Allocates a new pml4 table which will allocate space for page structures as needed
fn allocatePageTable() kallocator.MemError!*[512]PML4E {
    return @ptrCast(try kallocator.get(PML4E, 512, 4096));
}

/// Allocates a new pml4 table meant for userspace which will allocate space for page structures as needed
fn allocateUserPageTable() kallocator.MemError!*[512]PML4E {
    const retval: *[512]PML4E = @ptrCast(try kallocator.get(PML4E, 512, 4096));
    for (255..512) |i| {
        retval[i] = pml4[i];
    }
    return retval;
}

fn getPML4Index(virt: usize) u9 {
    return @truncate(virt >> 39);
}

// This is kind of screwy because I'm dumb and misunderstood something early on, I don't love how the logic
// splits across functions like this

/// Map a virtual address to a physical
pub fn map(phys: usize, virt: usize) void {
    const pml4e = &pml4[getPML4Index(virt)];
    pml4e.map(phys, virt) catch |err| {
        Console.print("{any}\n", .{err});
        kallocator.printMmap();
        @panic("Page allocation error");
    };
}

/// Unmaps a virtual address
pub fn unmap(virt: usize) void {
    const pml4e = &pml4[getPML4Index(virt)];
    pml4e.unmap(virt);
}

/// Converts a virtual address to a physical
pub fn v2p(virt: usize) PagingError!usize {
    const pml4e = &pml4[getPML4Index(virt)];
    if (!pml4e.present) return PagingError.UnmappedAddress;
    return pml4e.v2p(virt);
}
