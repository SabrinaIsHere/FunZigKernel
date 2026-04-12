#rm int.log; zig build run >&1 1>>int.log 2>&1; nvim int.log
		#--enable-kvm \
		#-cpu host \

qemu-system-x86_64 \
		-m 1G \
		-smp 1 \
		-nographic \
		--no-reboot \
		-d int \
		-D ./qemu.log \
		-cdrom "kernel.iso"
