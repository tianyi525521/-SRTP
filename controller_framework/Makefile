BUILD_DIR := build
SIM := $(BUILD_DIR)/tb_srtp_controller

.PHONY: test test-verilator clean

test:
	mkdir -p $(BUILD_DIR)
	iverilog -g2012 -o $(SIM) \
		rtl/srtp_types_pkg.sv \
		rtl/modified_region_tracker.sv \
		rtl/checkpoint_cost_estimator.sv \
		rtl/sleep_mode_selector.sv \
		rtl/srtp_controller_top.sv \
		tb/tb_srtp_controller_top.sv
	vvp $(SIM)

test-verilator:
	verilator --binary --timing -Wall -Wno-fatal \
		-Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
		--top-module tb_srtp_controller_top \
		rtl/srtp_types_pkg.sv \
		rtl/modified_region_tracker.sv \
		rtl/checkpoint_cost_estimator.sv \
		rtl/sleep_mode_selector.sv \
		rtl/srtp_controller_top.sv \
		tb/tb_srtp_controller_top.sv
	./obj_dir/Vtb_srtp_controller_top

clean:
	rm -rf $(BUILD_DIR) obj_dir

