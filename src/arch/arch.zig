//! Since at some point I'd like to target an architecture beyond IA-32, this provides a unified interface to call into
//! architecture stuff and which code is actually compiled can be controlled at compile time depending on the target
//! This is not meant to be called from 32 bit code, this is mostly to present an interface to multiarchitecture
//! 64 bit

pub const arch = @import("x86_64/arch.zig");

/// Initialize the target architecture
pub fn init() void {
    arch.init();
}
