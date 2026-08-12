//! Kallocator handles lower level memory region allocation while this handles more common
//! object allocation and zig allocator creation

const std = @import("std");
const main = @import("../main.zig");
const kallocator = @import("kallocator.zig");

const SlabAllocatorError = error{};

/// Initialize cache
pub fn init() void {}

/// Get a pointer to an object
pub fn getObject() void {}

/// Get a region of memory meant for a zig allocator
pub fn getAllocatorMem() void {}
