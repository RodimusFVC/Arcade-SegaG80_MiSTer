//  Universal Sound Board MM5837 noise
//  Based on MAME segausb.cpp (Aaron Giles, BSD-3-Clause)
//  This program is free software under the GNU General Public License v3.

`default_nettype none

module usb_noise (
	input  wire        clk,
	input  wire        reset,
	input  wire        tick,
	output wire        state
);
	logic [16:0] shift;

	assign state = shift[16];

	always_ff @(posedge clk) begin
		if (reset)      shift <= 17'h15555;
		else if (tick)  shift <= {shift[15:0], shift[13] ^ shift[16]};
	end
endmodule

`default_nettype wire
