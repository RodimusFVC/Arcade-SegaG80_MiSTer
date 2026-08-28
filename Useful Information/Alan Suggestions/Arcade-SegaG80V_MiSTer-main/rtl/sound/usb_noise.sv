//============================================================================
//  MM5837 noise source, Sega Universal Sound Board
//
//  Transcribed from refs/mame/segausb.cpp:
//
//    shift = (shift << 1) | (((shift >> 13) ^ (shift >> 16)) & 1)
//    state = (shift >> 16) & 1
//
//  Clocked at 100 kHz on the board, i.e. once every USB_2MHZ_CLOCK /
//  MM5837_CLOCK = 20 stream ticks. The divider is driven from outside so the
//  caller owns the rate.
//
//  The seed matters: an all-zero register is a lock-up state for this
//  polynomial, so MAME starts it at 0x15555 and so does this.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module usb_noise (
	input  wire        clk,
	input  wire        reset,
	input  wire        tick,     // one cycle per MM5837 clock
	output wire        state     // bit 16 of the shift register
);
	logic [16:0] shift;

	assign state = shift[16];

	always_ff @(posedge clk) begin
		if (reset)      shift <= 17'h15555;
		else if (tick)  shift <= {shift[15:0], shift[13] ^ shift[16]};
	end
endmodule

`default_nettype wire
