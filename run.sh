#rm int.log; zig build run >&1 1>>int.log 2>&1; nvim int.log

qemu-system-x86_64 \
		-m 1G \
		-cpu host \
		-smp 1 \
		-nographic \
		--no-reboot \
		--enable-kvm \
		-cdrom "kernel.iso"
