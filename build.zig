const std = @import("std");

// Gonna be real, zig build system is worse than makefiles almost purely because of how badly documented it is

pub fn build(b: *std.Build) !void {
    const gdb = b.option(bool, "gdb", "Debug with GDB") orelse false;

    const optimize = b.standardOptimizeOption(.{});

    const Target = std.Target.x86;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        // We use software float because we are disabling all SIMD stuff
        .cpu_features_add = Target.featureSet(&.{.soft_float}),
        // Disable all SIMD related stuff because SIMD are problematic in kernel
        .cpu_features_sub = Target.featureSet(&.{ .avx, .avx2, .sse, .sse2, .mmx }),
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .kernel,
        }),
    });
    kernel.setLinkerScript(b.path("src/linker.ld"));
    const installAssembly = b.addInstallBinFile(kernel.getEmittedAsm(), "kernel.s");
    b.getInstallStep().dependOn(&installAssembly.step);
    b.installArtifact(kernel);

    //const kernel_path = kernel.getEmittedBin();
    const isodir_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "mkdir", "-p", "isodir/boot/grub",
    });
    isodir_cmd.step.dependOn(b.getInstallStep());
    const install_kernel_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "cp", "zig-out/bin/kernel.elf", "isodir/boot/kernel.elf",
    });
    install_kernel_cmd.step.dependOn(&isodir_cmd.step);
    const install_grub_cfg_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "cp", "grub.cfg", "isodir/boot/grub/grub.cfg",
    });
    install_grub_cfg_cmd.step.dependOn(&install_kernel_cmd.step);
    const mk_iso_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "grub-mkrescue", "-o", "kernel.iso", "isodir",
    });
    mk_iso_cmd.step.dependOn(&install_grub_cfg_cmd.step);
    // zig fmt: on
    const qemu_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "qemu-system-x86_64",
        "-m", "1G",
        //"-cpu", "host",
        "-smp", "1",
        "--no-reboot",
        "--no-shutdown",
        "-nographic",
        //"--enable-kvm",
        "-D", "./qemu.log",
        "-d", "int", // Interrupt debugging
        "-cdrom", "kernel.iso"
    });
    if (gdb) qemu_cmd.addArgs(&[_][]const u8 {"-S", "-s"});
    qemu_cmd.step.dependOn(&mk_iso_cmd.step);
    // zig fmt: on
    //qemu_cmd.addArg("-kernel");
    //qemu_cmd.addFileArg(kernel_path);

    const run_cmd = b.addRunArtifact(kernel);
    run_cmd.step.dependOn(&qemu_cmd.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run kernel with qemu");
    run_step.dependOn(&qemu_cmd.step);

    const rm_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        "rm",  "-rf", "kernel.iso", "zig-out", "isodir", "*.log"
    });
    // zig fmt: on
    const clean_step = b.step("clean", "Remove artifacts");
    clean_step.dependOn(&rm_cmd.step);
}
