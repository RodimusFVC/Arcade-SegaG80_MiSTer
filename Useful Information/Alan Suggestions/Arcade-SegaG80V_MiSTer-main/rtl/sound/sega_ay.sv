//============================================================================
//  Zektor AY-3-8912
//
//  Zektor is the only G-80 X-Y game with a PSG. MAME wires it as:
//
//      AY8912(config, m_psg, VIDEO_CLOCK/4/2);          // 15468480/8
//      iospace.install_write_handler(0x3c, 0x3d, ... write_ay);
//      void write_ay(offs_t addr, uint8_t data) { m_psg->address_data_w(addr, data); }
//
//  address_data_w treats offset 0 as the address latch and offset 1 as the
//  data write, so $3C selects a register and $3D writes it.
//
//  MAME sets AY8910_RESISTOR_OUTPUT with 10k loads on all three channels, so
//  the outputs are summed passively; jt49's per-channel linearised outputs are
//  summed here to match rather than using its pre-mixed `sound`.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_ay #(
	// clk_12 is 12.096 MHz; the AY runs at 15468480/8 = 1.93356 MHz
	parameter int CLK_HZ = 12_096_000,
	parameter int AY_HZ  = 1_933_560
) (
	input  wire        clk,
	input  wire        reset,

	input  wire        wr,        // one cycle, from the $3C/$3D I/O strobe
	input  wire        addr_sel,  // 0 = $3C (address latch), 1 = $3D (data)
	input  wire  [7:0] din,

	output wire signed [15:0] audio   // DC-blocked, signed
);

	// AY clock enable, fractional off clk
	logic [23:0] acc;
	logic        ce_ay;

	always_ff @(posedge clk) begin
		if (reset) begin
			acc   <= '0;
			ce_ay <= 1'b0;
		end else if (acc + AY_HZ >= CLK_HZ) begin
			acc   <= acc + AY_HZ - CLK_HZ;
			ce_ay <= 1'b1;
		end else begin
			acc   <= acc + AY_HZ;
			ce_ay <= 1'b0;
		end
	end

	// Latch the selected register on a $3C write, then present a write cycle to
	// jt49 on a $3D write. jt49 samples on its own clock enable, so the strobe
	// is stretched until the next one.
	logic [3:0] reg_addr;
	logic       pending;
	logic [7:0] pending_data;

	always_ff @(posedge clk) begin
		if (reset) begin
			reg_addr     <= 4'd0;
			pending      <= 1'b0;
			pending_data <= 8'd0;
		end else begin
			if (wr) begin
				if (!addr_sel) reg_addr <= din[3:0];
				else begin
					pending      <= 1'b1;
					pending_data <= din;
				end
			end
			if (pending && ce_ay) pending <= 1'b0;
		end
	end

	wire [7:0] ch_a, ch_b, ch_c;

	jt49 psg (
		.rst_n   (~reset),
		.clk     (clk),
		.clk_en  (ce_ay),
		.addr    (reg_addr),
		.cs_n    (1'b0),
		.wr_n    (~pending),
		.din     (pending_data),
		.sel     (1'b1),          // no extra divide; ce_ay is already the AY rate
		.dout    (),
		.sound   (),
		.A       (ch_a),
		.B       (ch_b),
		.C       (ch_c),
		.sample  (),
		.IOA_in  (8'hFF), .IOA_out(), .IOA_oe(),
		.IOB_in  (8'hFF), .IOB_out(), .IOB_oe()
	);

	// passive resistor sum, matching AY8910_RESISTOR_OUTPUT with equal loads
	// jt49 presents each channel as an unsigned 0..255 envelope, so the sum
	// is unipolar 0..765 and carries a DC term that grows with volume. The
	// board couples its output through a capacitor, so do the same here —
	// feeding the raw unsigned value to the mixer offsets the whole output and
	// thumps whenever the volume changes.
	wire [10:0] raw = {3'd0, ch_a} + {3'd0, ch_b} + {3'd0, ch_c};
	wire signed [20:0] x = $signed({5'd0, raw, 5'd0});     // 0..24480

	logic signed [20:0] dc;
	always_ff @(posedge clk) begin
		if (reset)       dc <= '0;
		else if (ce_ay)  dc <= dc + ((x - dc) >>> 15);      // ~10 Hz
	end

	wire signed [20:0] ac = x - dc;
	assign audio = (ac >  21'sd32767) ?  16'sh7FFF :
	               (ac < -21'sd32768) ? -16'sh8000 : ac[15:0];

endmodule

`default_nettype wire
