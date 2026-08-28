// ============================================================================
// Local bloom stage for the delayed primary stream.
// written 2026 by Videodr0me
//
// Applies the bloom source curve, runs the local blur passes, and combines
// the result with the primary image.
// ============================================================================

module vfb_filter (
	input  logic        clk_sys,
	input  logic        ce_pix,
	input  logic        reset,

	// Bloom controls
	input  logic [2:0]  osd_bloom_width,
	input  logic [9:0]  bloom_curve_gain,

	// Delayed primary image
	input  logic [7:0]  VGA_R_IN,
	input  logic [7:0]  VGA_G_IN,
	input  logic [7:0]  VGA_B_IN,
	input  logic        VGA_HS_IN,
	input  logic        VGA_VS_IN,
	input  logic        VGA_HBLANK_IN,
	input  logic        VGA_VBLANK_IN,

	// Filtered output
	output logic [7:0]  VGA_R_OUT,
	output logic [7:0]  VGA_G_OUT,
	output logic [7:0]  VGA_B_OUT,
	output logic        VGA_HS_OUT,
	output logic        VGA_VS_OUT,
	output logic        VGA_HBLANK_OUT,
	output logic        VGA_VBLANK_OUT
);

	logic [2:0] osd_bloom_width_q = 3'd0;
	logic [9:0] bloom_curve_gain_q = 10'd64;
	always_ff @(posedge clk_sys) begin
		osd_bloom_width_q <= osd_bloom_width;
		bloom_curve_gain_q <= bloom_curve_gain;
	end

	logic [7:0] vga_r_in_r;
	logic [7:0] vga_g_in_r;
	logic [7:0] vga_b_in_r;
	logic       vga_hs_in_r;
	logic       vga_vs_in_r;
	logic       vga_hblank_in_r;
	logic       vga_vblank_in_r;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			vga_r_in_r <= 8'd0;
			vga_g_in_r <= 8'd0;
			vga_b_in_r <= 8'd0;
			vga_hs_in_r <= 1'b1;
			vga_vs_in_r <= 1'b1;
			vga_hblank_in_r <= 1'b1;
			vga_vblank_in_r <= 1'b1;
		end else if (ce_pix) begin
			vga_r_in_r <= VGA_R_IN;
			vga_g_in_r <= VGA_G_IN;
			vga_b_in_r <= VGA_B_IN;
			vga_hs_in_r <= VGA_HS_IN;
			vga_vs_in_r <= VGA_VS_IN;
			vga_hblank_in_r <= VGA_HBLANK_IN;
			vga_vblank_in_r <= VGA_VBLANK_IN;
		end
	end

	logic [8:0] bloom_comp_scale;
	always_comb begin
		case (osd_bloom_width_q)
			3'd0: bloom_comp_scale = 9'd0;    // Off
			3'd1: bloom_comp_scale = 9'd24;   // Thin
			3'd2: bloom_comp_scale = 9'd43;   // Tight
			3'd3: bloom_comp_scale = 9'd80;   // Soft
			3'd4: bloom_comp_scale = 9'd114;  // Normal
			3'd5: bloom_comp_scale = 9'd180;  // Broad
			3'd6: bloom_comp_scale = 9'd240;  // Wide-
			default: bloom_comp_scale = 9'd320; // Wide
		endcase
	end

	// Bloom source curve: round(255 * (channel / 255)^2.5).
	//
	// Three 256x8 ROMs provide one independent lookup per RGB channel.
	function automatic [7:0] bloom_curve25_value(input logic [7:0] value);
		begin
			case (value)
				8'd0: bloom_curve25_value = 8'd0;
				8'd1: bloom_curve25_value = 8'd0;
				8'd2: bloom_curve25_value = 8'd0;
				8'd3: bloom_curve25_value = 8'd0;
				8'd4: bloom_curve25_value = 8'd0;
				8'd5: bloom_curve25_value = 8'd0;
				8'd6: bloom_curve25_value = 8'd0;
				8'd7: bloom_curve25_value = 8'd0;
				8'd8: bloom_curve25_value = 8'd0;
				8'd9: bloom_curve25_value = 8'd0;
				8'd10: bloom_curve25_value = 8'd0;
				8'd11: bloom_curve25_value = 8'd0;
				8'd12: bloom_curve25_value = 8'd0;
				8'd13: bloom_curve25_value = 8'd0;
				8'd14: bloom_curve25_value = 8'd0;
				8'd15: bloom_curve25_value = 8'd0;
				8'd16: bloom_curve25_value = 8'd0;
				8'd17: bloom_curve25_value = 8'd0;
				8'd18: bloom_curve25_value = 8'd0;
				8'd19: bloom_curve25_value = 8'd0;
				8'd20: bloom_curve25_value = 8'd0;
				8'd21: bloom_curve25_value = 8'd0;
				8'd22: bloom_curve25_value = 8'd1;
				8'd23: bloom_curve25_value = 8'd1;
				8'd24: bloom_curve25_value = 8'd1;
				8'd25: bloom_curve25_value = 8'd1;
				8'd26: bloom_curve25_value = 8'd1;
				8'd27: bloom_curve25_value = 8'd1;
				8'd28: bloom_curve25_value = 8'd1;
				8'd29: bloom_curve25_value = 8'd1;
				8'd30: bloom_curve25_value = 8'd1;
				8'd31: bloom_curve25_value = 8'd1;
				8'd32: bloom_curve25_value = 8'd1;
				8'd33: bloom_curve25_value = 8'd2;
				8'd34: bloom_curve25_value = 8'd2;
				8'd35: bloom_curve25_value = 8'd2;
				8'd36: bloom_curve25_value = 8'd2;
				8'd37: bloom_curve25_value = 8'd2;
				8'd38: bloom_curve25_value = 8'd2;
				8'd39: bloom_curve25_value = 8'd2;
				8'd40: bloom_curve25_value = 8'd2;
				8'd41: bloom_curve25_value = 8'd3;
				8'd42: bloom_curve25_value = 8'd3;
				8'd43: bloom_curve25_value = 8'd3;
				8'd44: bloom_curve25_value = 8'd3;
				8'd45: bloom_curve25_value = 8'd3;
				8'd46: bloom_curve25_value = 8'd4;
				8'd47: bloom_curve25_value = 8'd4;
				8'd48: bloom_curve25_value = 8'd4;
				8'd49: bloom_curve25_value = 8'd4;
				8'd50: bloom_curve25_value = 8'd4;
				8'd51: bloom_curve25_value = 8'd5;
				8'd52: bloom_curve25_value = 8'd5;
				8'd53: bloom_curve25_value = 8'd5;
				8'd54: bloom_curve25_value = 8'd5;
				8'd55: bloom_curve25_value = 8'd6;
				8'd56: bloom_curve25_value = 8'd6;
				8'd57: bloom_curve25_value = 8'd6;
				8'd58: bloom_curve25_value = 8'd6;
				8'd59: bloom_curve25_value = 8'd7;
				8'd60: bloom_curve25_value = 8'd7;
				8'd61: bloom_curve25_value = 8'd7;
				8'd62: bloom_curve25_value = 8'd7;
				8'd63: bloom_curve25_value = 8'd8;
				8'd64: bloom_curve25_value = 8'd8;
				8'd65: bloom_curve25_value = 8'd8;
				8'd66: bloom_curve25_value = 8'd9;
				8'd67: bloom_curve25_value = 8'd9;
				8'd68: bloom_curve25_value = 8'd9;
				8'd69: bloom_curve25_value = 8'd10;
				8'd70: bloom_curve25_value = 8'd10;
				8'd71: bloom_curve25_value = 8'd10;
				8'd72: bloom_curve25_value = 8'd11;
				8'd73: bloom_curve25_value = 8'd11;
				8'd74: bloom_curve25_value = 8'd12;
				8'd75: bloom_curve25_value = 8'd12;
				8'd76: bloom_curve25_value = 8'd12;
				8'd77: bloom_curve25_value = 8'd13;
				8'd78: bloom_curve25_value = 8'd13;
				8'd79: bloom_curve25_value = 8'd14;
				8'd80: bloom_curve25_value = 8'd14;
				8'd81: bloom_curve25_value = 8'd15;
				8'd82: bloom_curve25_value = 8'd15;
				8'd83: bloom_curve25_value = 8'd15;
				8'd84: bloom_curve25_value = 8'd16;
				8'd85: bloom_curve25_value = 8'd16;
				8'd86: bloom_curve25_value = 8'd17;
				8'd87: bloom_curve25_value = 8'd17;
				8'd88: bloom_curve25_value = 8'd18;
				8'd89: bloom_curve25_value = 8'd18;
				8'd90: bloom_curve25_value = 8'd19;
				8'd91: bloom_curve25_value = 8'd19;
				8'd92: bloom_curve25_value = 8'd20;
				8'd93: bloom_curve25_value = 8'd20;
				8'd94: bloom_curve25_value = 8'd21;
				8'd95: bloom_curve25_value = 8'd22;
				8'd96: bloom_curve25_value = 8'd22;
				8'd97: bloom_curve25_value = 8'd23;
				8'd98: bloom_curve25_value = 8'd23;
				8'd99: bloom_curve25_value = 8'd24;
				8'd100: bloom_curve25_value = 8'd25;
				8'd101: bloom_curve25_value = 8'd25;
				8'd102: bloom_curve25_value = 8'd26;
				8'd103: bloom_curve25_value = 8'd26;
				8'd104: bloom_curve25_value = 8'd27;
				8'd105: bloom_curve25_value = 8'd28;
				8'd106: bloom_curve25_value = 8'd28;
				8'd107: bloom_curve25_value = 8'd29;
				8'd108: bloom_curve25_value = 8'd30;
				8'd109: bloom_curve25_value = 8'd30;
				8'd110: bloom_curve25_value = 8'd31;
				8'd111: bloom_curve25_value = 8'd32;
				8'd112: bloom_curve25_value = 8'd33;
				8'd113: bloom_curve25_value = 8'd33;
				8'd114: bloom_curve25_value = 8'd34;
				8'd115: bloom_curve25_value = 8'd35;
				8'd116: bloom_curve25_value = 8'd36;
				8'd117: bloom_curve25_value = 8'd36;
				8'd118: bloom_curve25_value = 8'd37;
				8'd119: bloom_curve25_value = 8'd38;
				8'd120: bloom_curve25_value = 8'd39;
				8'd121: bloom_curve25_value = 8'd40;
				8'd122: bloom_curve25_value = 8'd40;
				8'd123: bloom_curve25_value = 8'd41;
				8'd124: bloom_curve25_value = 8'd42;
				8'd125: bloom_curve25_value = 8'd43;
				8'd126: bloom_curve25_value = 8'd44;
				8'd127: bloom_curve25_value = 8'd45;
				8'd128: bloom_curve25_value = 8'd46;
				8'd129: bloom_curve25_value = 8'd46;
				8'd130: bloom_curve25_value = 8'd47;
				8'd131: bloom_curve25_value = 8'd48;
				8'd132: bloom_curve25_value = 8'd49;
				8'd133: bloom_curve25_value = 8'd50;
				8'd134: bloom_curve25_value = 8'd51;
				8'd135: bloom_curve25_value = 8'd52;
				8'd136: bloom_curve25_value = 8'd53;
				8'd137: bloom_curve25_value = 8'd54;
				8'd138: bloom_curve25_value = 8'd55;
				8'd139: bloom_curve25_value = 8'd56;
				8'd140: bloom_curve25_value = 8'd57;
				8'd141: bloom_curve25_value = 8'd58;
				8'd142: bloom_curve25_value = 8'd59;
				8'd143: bloom_curve25_value = 8'd60;
				8'd144: bloom_curve25_value = 8'd61;
				8'd145: bloom_curve25_value = 8'd62;
				8'd146: bloom_curve25_value = 8'd63;
				8'd147: bloom_curve25_value = 8'd64;
				8'd148: bloom_curve25_value = 8'd65;
				8'd149: bloom_curve25_value = 8'd67;
				8'd150: bloom_curve25_value = 8'd68;
				8'd151: bloom_curve25_value = 8'd69;
				8'd152: bloom_curve25_value = 8'd70;
				8'd153: bloom_curve25_value = 8'd71;
				8'd154: bloom_curve25_value = 8'd72;
				8'd155: bloom_curve25_value = 8'd73;
				8'd156: bloom_curve25_value = 8'd75;
				8'd157: bloom_curve25_value = 8'd76;
				8'd158: bloom_curve25_value = 8'd77;
				8'd159: bloom_curve25_value = 8'd78;
				8'd160: bloom_curve25_value = 8'd80;
				8'd161: bloom_curve25_value = 8'd81;
				8'd162: bloom_curve25_value = 8'd82;
				8'd163: bloom_curve25_value = 8'd83;
				8'd164: bloom_curve25_value = 8'd85;
				8'd165: bloom_curve25_value = 8'd86;
				8'd166: bloom_curve25_value = 8'd87;
				8'd167: bloom_curve25_value = 8'd89;
				8'd168: bloom_curve25_value = 8'd90;
				8'd169: bloom_curve25_value = 8'd91;
				8'd170: bloom_curve25_value = 8'd93;
				8'd171: bloom_curve25_value = 8'd94;
				8'd172: bloom_curve25_value = 8'd95;
				8'd173: bloom_curve25_value = 8'd97;
				8'd174: bloom_curve25_value = 8'd98;
				8'd175: bloom_curve25_value = 8'd99;
				8'd176: bloom_curve25_value = 8'd101;
				8'd177: bloom_curve25_value = 8'd102;
				8'd178: bloom_curve25_value = 8'd104;
				8'd179: bloom_curve25_value = 8'd105;
				8'd180: bloom_curve25_value = 8'd107;
				8'd181: bloom_curve25_value = 8'd108;
				8'd182: bloom_curve25_value = 8'd110;
				8'd183: bloom_curve25_value = 8'd111;
				8'd184: bloom_curve25_value = 8'd113;
				8'd185: bloom_curve25_value = 8'd114;
				8'd186: bloom_curve25_value = 8'd116;
				8'd187: bloom_curve25_value = 8'd117;
				8'd188: bloom_curve25_value = 8'd119;
				8'd189: bloom_curve25_value = 8'd121;
				8'd190: bloom_curve25_value = 8'd122;
				8'd191: bloom_curve25_value = 8'd124;
				8'd192: bloom_curve25_value = 8'd125;
				8'd193: bloom_curve25_value = 8'd127;
				8'd194: bloom_curve25_value = 8'd129;
				8'd195: bloom_curve25_value = 8'd130;
				8'd196: bloom_curve25_value = 8'd132;
				8'd197: bloom_curve25_value = 8'd134;
				8'd198: bloom_curve25_value = 8'd135;
				8'd199: bloom_curve25_value = 8'd137;
				8'd200: bloom_curve25_value = 8'd139;
				8'd201: bloom_curve25_value = 8'd141;
				8'd202: bloom_curve25_value = 8'd142;
				8'd203: bloom_curve25_value = 8'd144;
				8'd204: bloom_curve25_value = 8'd146;
				8'd205: bloom_curve25_value = 8'd148;
				8'd206: bloom_curve25_value = 8'd150;
				8'd207: bloom_curve25_value = 8'd151;
				8'd208: bloom_curve25_value = 8'd153;
				8'd209: bloom_curve25_value = 8'd155;
				8'd210: bloom_curve25_value = 8'd157;
				8'd211: bloom_curve25_value = 8'd159;
				8'd212: bloom_curve25_value = 8'd161;
				8'd213: bloom_curve25_value = 8'd163;
				8'd214: bloom_curve25_value = 8'd165;
				8'd215: bloom_curve25_value = 8'd166;
				8'd216: bloom_curve25_value = 8'd168;
				8'd217: bloom_curve25_value = 8'd170;
				8'd218: bloom_curve25_value = 8'd172;
				8'd219: bloom_curve25_value = 8'd174;
				8'd220: bloom_curve25_value = 8'd176;
				8'd221: bloom_curve25_value = 8'd178;
				8'd222: bloom_curve25_value = 8'd180;
				8'd223: bloom_curve25_value = 8'd182;
				8'd224: bloom_curve25_value = 8'd184;
				8'd225: bloom_curve25_value = 8'd186;
				8'd226: bloom_curve25_value = 8'd189;
				8'd227: bloom_curve25_value = 8'd191;
				8'd228: bloom_curve25_value = 8'd193;
				8'd229: bloom_curve25_value = 8'd195;
				8'd230: bloom_curve25_value = 8'd197;
				8'd231: bloom_curve25_value = 8'd199;
				8'd232: bloom_curve25_value = 8'd201;
				8'd233: bloom_curve25_value = 8'd204;
				8'd234: bloom_curve25_value = 8'd206;
				8'd235: bloom_curve25_value = 8'd208;
				8'd236: bloom_curve25_value = 8'd210;
				8'd237: bloom_curve25_value = 8'd212;
				8'd238: bloom_curve25_value = 8'd215;
				8'd239: bloom_curve25_value = 8'd217;
				8'd240: bloom_curve25_value = 8'd219;
				8'd241: bloom_curve25_value = 8'd221;
				8'd242: bloom_curve25_value = 8'd224;
				8'd243: bloom_curve25_value = 8'd226;
				8'd244: bloom_curve25_value = 8'd228;
				8'd245: bloom_curve25_value = 8'd231;
				8'd246: bloom_curve25_value = 8'd233;
				8'd247: bloom_curve25_value = 8'd235;
				8'd248: bloom_curve25_value = 8'd238;
				8'd249: bloom_curve25_value = 8'd240;
				8'd250: bloom_curve25_value = 8'd243;
				8'd251: bloom_curve25_value = 8'd245;
				8'd252: bloom_curve25_value = 8'd248;
				8'd253: bloom_curve25_value = 8'd250;
				8'd254: bloom_curve25_value = 8'd253;
				8'd255: bloom_curve25_value = 8'd255;
				default: bloom_curve25_value = 8'd0;
			endcase
		end
	endfunction

	(* ramstyle = "MLAB" *) logic [7:0] bloom_curve25_rom_r [0:255];
	(* ramstyle = "MLAB" *) logic [7:0] bloom_curve25_rom_g [0:255];
	(* ramstyle = "MLAB" *) logic [7:0] bloom_curve25_rom_b [0:255];

	integer bloom_curve25_init_i;
	initial begin
		for (bloom_curve25_init_i = 0;
		     bloom_curve25_init_i < 256;
		     bloom_curve25_init_i = bloom_curve25_init_i + 1) begin
			bloom_curve25_rom_r[bloom_curve25_init_i] =
				bloom_curve25_value(bloom_curve25_init_i[7:0]);
			bloom_curve25_rom_g[bloom_curve25_init_i] =
				bloom_curve25_value(bloom_curve25_init_i[7:0]);
			bloom_curve25_rom_b[bloom_curve25_init_i] =
				bloom_curve25_value(bloom_curve25_init_i[7:0]);
		end
	end

	function automatic [7:0] apply_curve_gain(
		input logic [7:0] curved,
		input logic [9:0] gain
	);
		logic [11:0] scaled;
		logic [8:0] scaled9;
		begin
			case (gain)
				10'd64: begin
					apply_curve_gain = {2'b00, curved[7:2]};
				end
				10'd96: begin
					scaled =
						({4'd0, curved} << 1) +
						{4'd0, curved} + 12'd4;
					apply_curve_gain = {1'b0, scaled[9:3]};
				end
				10'd128: begin
					apply_curve_gain = {1'b0, curved[7:1]};
				end
				10'd192: begin
					scaled =
						({4'd0, curved} << 1) +
						{4'd0, curved} + 12'd2;
					apply_curve_gain = scaled[9:2];
				end
				10'd256: begin
					apply_curve_gain = curved;
				end
				10'd320: begin
					scaled =
						({4'd0, curved} << 2) +
						{4'd0, curved} + 12'd2;
					scaled9 = scaled[10:2];
					apply_curve_gain =
						scaled9[8] ? 8'hff : scaled9[7:0];
				end
				10'd384: begin
					scaled =
						({4'd0, curved} << 1) +
						{4'd0, curved} + 12'd1;
					scaled9 = scaled[9:1];
					apply_curve_gain =
						scaled9[8] ? 8'hff : scaled9[7:0];
				end
				default: begin
					apply_curve_gain =
						curved[7] ? 8'hff :
						{curved[6:0], 1'b0};
				end
			endcase
		end
	endfunction

	logic en_p1, en_p2, en_p3;
	always_comb begin
		en_p1 = (osd_bloom_width_q >= 3'd1);
		en_p2 = (osd_bloom_width_q >= 3'd3);
		en_p3 = (osd_bloom_width_q >= 3'd5);
	end

	// Delay sync and blanking to match RGB.
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_0 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_1 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_2 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_3 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_4 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_5 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_6 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_7 [0:2047];
	(* ramstyle = "M10K, no_rw_check" *) logic [3:0] sync_lb_8 [0:2047];

	logic [3:0] s_lb_out [0:8];

	logic [10:0] h_count;
	logic [10:0] h_count_d1;
	logic hs_d;

	logic [33:0] hs_pipe, vs_pipe, hb_pipe, vb_pipe;
	logic [3:0]  sync_in_d1;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			hs_pipe <= '0;
			vs_pipe <= '0;
			hb_pipe <= '1;
			vb_pipe <= '1;
			h_count <= '0;
			hs_d <= '0;
			sync_in_d1 <= 4'b0011;
		end else if (ce_pix) begin
			hs_d <= vga_hs_in_r;
			sync_in_d1 <= {
				vga_hs_in_r,
				vga_vs_in_r,
				vga_hblank_in_r,
				vga_vblank_in_r
			};

			if (vga_hs_in_r && !hs_d) h_count <= 0;
			else if (h_count < 11'd2047) h_count <= h_count + 11'd1;

			h_count_d1 <= h_count;

			s_lb_out[0] <= sync_lb_0[h_count];
			s_lb_out[1] <= sync_lb_1[h_count];
			s_lb_out[2] <= sync_lb_2[h_count];
			s_lb_out[3] <= sync_lb_3[h_count];
			s_lb_out[4] <= sync_lb_4[h_count];
			s_lb_out[5] <= sync_lb_5[h_count];
			s_lb_out[6] <= sync_lb_6[h_count];
			s_lb_out[7] <= sync_lb_7[h_count];
			s_lb_out[8] <= sync_lb_8[h_count];

			sync_lb_0[h_count_d1] <= sync_in_d1;
			sync_lb_1[h_count_d1] <= s_lb_out[0];
			sync_lb_2[h_count_d1] <= s_lb_out[1];
			sync_lb_3[h_count_d1] <= s_lb_out[2];
			sync_lb_4[h_count_d1] <= s_lb_out[3];
			sync_lb_5[h_count_d1] <= s_lb_out[4];
			sync_lb_6[h_count_d1] <= s_lb_out[5];
			sync_lb_7[h_count_d1] <= s_lb_out[6];
			sync_lb_8[h_count_d1] <= s_lb_out[7];

			hs_pipe <= {hs_pipe[32:0], s_lb_out[8][3]};
			vs_pipe <= {vs_pipe[32:0], s_lb_out[8][2]};
			hb_pipe <= {hb_pipe[32:0], s_lb_out[8][1]};
			vb_pipe <= {vb_pipe[32:0], s_lb_out[8][0]};
		end
	end

	// Track horizontal position through the filter.
	localparam integer COMP_SERVICE_STAGE = 30;
	localparam integer COMP_WRITE_STAGE = 31;
	localparam integer COMP_PRESENT_READ_STAGE = 32;
	localparam integer COMP_OUTPUT_SYNC_STAGE = 30;
	logic [10:0] active_x;
	logic [10:0] ax_pipe [1:33];
	logic        ax_valid_pipe [1:33];

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			active_x <= 11'd0;
			for (int i=1; i<=33; i++) ax_pipe[i] <= 11'd0;
			for (int i=1; i<=33; i++) ax_valid_pipe[i] <= 1'b0;
		end else if (ce_pix) begin
			if (vga_hblank_in_r) begin
				active_x <= 11'd0;
			end else begin
				if (active_x < 11'd1471)
					active_x <= active_x + 11'd1;
			end

			ax_pipe[1] <= vga_hblank_in_r ? 11'd0 : active_x;
			for (int i=2; i<=33; i++) ax_pipe[i] <= ax_pipe[i-1];

			ax_valid_pipe[1] <= !vga_hblank_in_r;
			for (int i=2; i<=33; i++)
				ax_valid_pipe[i] <= ax_valid_pipe[i-1];
		end
	end

	logic [7:0] source_r, source_g, source_b;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			source_r <= vga_r_in_r;
			source_g <= vga_g_in_r;
			source_b <= vga_b_in_r;
		end
	end

	// Register primary RGB and look up the bloom source.
	logic [23:0] base_24;
	logic [7:0] bloom_curve_r, bloom_curve_g, bloom_curve_b;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			base_24 <= {source_r, source_g, source_b};

			bloom_curve_r <= bloom_curve25_rom_r[source_r];
			bloom_curve_g <= bloom_curve25_rom_g[source_g];
			bloom_curve_b <= bloom_curve25_rom_b[source_b];
		end
	end

	// Delay primary RGB by six lines.
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] base_lb_0 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] base_lb_1 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] base_lb_2 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] base_lb_3 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] base_lb_4 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] base_lb_5 [0:1471];

	logic [23:0] base_lb_0_ram, base_lb_1_ram, base_lb_2_ram, base_lb_3_ram, base_lb_4_ram, base_lb_5_ram;
	logic [10:0] base_cascade_addr;
	logic        base_cascade_valid;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			base_cascade_addr <= 11'd0;
			base_cascade_valid <= 1'b0;
		end else if (ce_pix) begin
			base_cascade_addr <= ax_pipe[1];
			base_cascade_valid <= ax_valid_pipe[1];

			base_lb_0_ram <= base_lb_0[ax_pipe[1]];
			base_lb_1_ram <= base_lb_1[ax_pipe[1]];
			base_lb_2_ram <= base_lb_2[ax_pipe[1]];
			base_lb_3_ram <= base_lb_3[ax_pipe[1]];
			base_lb_4_ram <= base_lb_4[ax_pipe[1]];
			base_lb_5_ram <= base_lb_5[ax_pipe[1]];

			if (ax_valid_pipe[2])
				base_lb_0[ax_pipe[2]] <= base_24;

			if (base_cascade_valid) begin
				base_lb_1[base_cascade_addr] <= base_lb_0_ram;
				base_lb_2[base_cascade_addr] <= base_lb_1_ram;
				base_lb_3[base_cascade_addr] <= base_lb_2_ram;
				base_lb_4[base_cascade_addr] <= base_lb_3_ram;
				base_lb_5[base_cascade_addr] <= base_lb_4_ram;
			end
		end
	end

	logic [23:0] base_align_pipe [1:28];
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			base_align_pipe[1] <= base_lb_5_ram;
			for (int i = 2; i <= 28; i++) base_align_pipe[i] <= base_align_pipe[i-1];
		end
	end

	// Apply bloom source gain.
	logic [23:0] bloom_src;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			bloom_src[23:16] <=
				apply_curve_gain(bloom_curve_r, bloom_curve_gain_q);
			bloom_src[15:8] <=
				apply_curve_gain(bloom_curve_g, bloom_curve_gain_q);
			bloom_src[7:0] <=
				apply_curve_gain(bloom_curve_b, bloom_curve_gain_q);
		end
	end

	// Three bloom passes.
	logic [10:0] hc_p1, hc_p2;
	logic hb_p1, hb_p2;
	logic [23:0] b_p1, b_p2, b_p3;

	vfb_blur bloom_pass1 (.clk_sys(clk_sys), .ce_pix(ce_pix), .reset(reset), .active_x_in(ax_pipe[3]), .hblank_in(hb_pipe[3]), .enable(en_p1), .rgb_in(bloom_src), .active_x_out(hc_p1), .hblank_out(hb_p1), .rgb_out(b_p1));
	vfb_blur bloom_pass2 (.clk_sys(clk_sys), .ce_pix(ce_pix), .reset(reset), .active_x_in(hc_p1), .hblank_in(hb_p1), .enable(en_p2), .rgb_in(b_p1), .active_x_out(hc_p2), .hblank_out(hb_p2), .rgb_out(b_p2));
	vfb_blur bloom_pass3 (.clk_sys(clk_sys), .ce_pix(ce_pix), .reset(reset), .active_x_in(hc_p2), .hblank_in(hb_p2), .enable(en_p3), .rgb_in(b_p2), .active_x_out(), .hblank_out(), .rgb_out(b_p3));

	// Scale the bloom result.
	logic [7:0] bloom_comp_r, bloom_comp_g, bloom_comp_b;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			logic [16:0] cr, cg, cb;
			cr = 17'(b_p3[23:16]) * 17'(bloom_comp_scale);
			cg = 17'(b_p3[15:8])  * 17'(bloom_comp_scale);
			cb = 17'(b_p3[7:0])   * 17'(bloom_comp_scale);

			bloom_comp_r <= (cr[16:12] > 5'd0) ? 8'd255 : cr[11:4];
			bloom_comp_g <= (cg[16:12] > 5'd0) ? 8'd255 : cg[11:4];
			bloom_comp_b <= (cb[16:12] > 5'd0) ? 8'd255 : cb[11:4];
		end
	end

	logic [7:0] bcomp_r_d1, bcomp_g_d1, bcomp_b_d1;
	logic [7:0] bcomp_r_d2, bcomp_g_d2, bcomp_b_d2;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			bcomp_r_d1 <= bloom_comp_r;
			bcomp_g_d1 <= bloom_comp_g;
			bcomp_b_d1 <= bloom_comp_b;
			bcomp_r_d2 <= bcomp_r_d1;
			bcomp_g_d2 <= bcomp_g_d1;
			bcomp_b_d2 <= bcomp_b_d1;
		end
	end

	// Combine primary and bloom by channel maximum.
	logic [7:0] comp_r, comp_g, comp_b;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			comp_r <= (bcomp_r_d2 > base_align_pipe[28][23:16]) ? bcomp_r_d2 : base_align_pipe[28][23:16];
			comp_g <= (bcomp_g_d2 > base_align_pipe[28][15:8])  ? bcomp_g_d2 : base_align_pipe[28][15:8];
			comp_b <= (bcomp_b_d2 > base_align_pipe[28][7:0])   ? bcomp_b_d2 : base_align_pipe[28][7:0];
		end
	end

	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_0 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_1 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_2 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] comp_lb_3 [0:1471];

	logic [23:0] clb_0, clb_1, clb_2, clb_3;
	logic [10:0] comp_cascade_addr;
	logic        comp_cascade_valid;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			comp_cascade_addr <= 11'd0;
			comp_cascade_valid <= 1'b0;
		end else if (ce_pix) begin
			comp_cascade_addr <= ax_pipe[COMP_SERVICE_STAGE];
			comp_cascade_valid <= ax_valid_pipe[COMP_SERVICE_STAGE];

			clb_0 <= comp_lb_0[ax_pipe[COMP_SERVICE_STAGE]];
			clb_1 <= comp_lb_1[ax_pipe[COMP_SERVICE_STAGE]];
			clb_2 <= comp_lb_2[ax_pipe[COMP_SERVICE_STAGE]];
			// Read the final delayed row at the output position. Advance the
			// line buffers only for active pixels.
			clb_3 <= comp_lb_3[ax_pipe[COMP_PRESENT_READ_STAGE]];

			if (ax_valid_pipe[COMP_WRITE_STAGE])
				comp_lb_0[ax_pipe[COMP_WRITE_STAGE]] <= {comp_r, comp_g, comp_b};

			if (comp_cascade_valid) begin
				comp_lb_1[comp_cascade_addr] <= clb_0;
				comp_lb_2[comp_cascade_addr] <= clb_1;
				comp_lb_3[comp_cascade_addr] <= clb_2;
			end
		end
	end

	logic [7:0] comp_r_d1, comp_g_d1, comp_b_d1;
	assign comp_r_d1 = clb_3[23:16];
	assign comp_g_d1 = clb_3[15:8];
	assign comp_b_d1 = clb_3[7:0];

	// Register RGB and timing outputs.
	logic [7:0] mix_r, mix_g, mix_b;
	logic mix_hs, mix_vs, mix_hblank, mix_vblank;
	logic out_hs, out_vs, out_hblank, out_vblank;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			mix_r <= 8'd0;
			mix_g <= 8'd0;
			mix_b <= 8'd0;
			mix_hs <= 1'b1;
			mix_vs <= 1'b1;
			mix_hblank <= 1'b1;
			mix_vblank <= 1'b1;
			out_hs <= 1'b1;
			out_vs <= 1'b1;
			out_hblank <= 1'b1;
			out_vblank <= 1'b1;
			VGA_R_OUT <= 8'd0;
			VGA_G_OUT <= 8'd0;
			VGA_B_OUT <= 8'd0;
			VGA_HS_OUT <= 1'b1;
			VGA_VS_OUT <= 1'b1;
			VGA_HBLANK_OUT <= 1'b1;
			VGA_VBLANK_OUT <= 1'b1;
		end else if (ce_pix) begin
			mix_r <= comp_r_d1;
			mix_g <= comp_g_d1;
			mix_b <= comp_b_d1;
			mix_hs <= hs_pipe[COMP_OUTPUT_SYNC_STAGE];
			mix_vs <= vs_pipe[COMP_OUTPUT_SYNC_STAGE];
			mix_hblank <= hb_pipe[COMP_OUTPUT_SYNC_STAGE];
			mix_vblank <= vb_pipe[COMP_OUTPUT_SYNC_STAGE];

			out_hs <= mix_hs;
			out_vs <= mix_vs;
			out_hblank <= mix_hblank;
			out_vblank <= mix_vblank;

			VGA_R_OUT <= mix_r;
			VGA_G_OUT <= mix_g;
			VGA_B_OUT <= mix_b;
			VGA_HS_OUT <= out_hs;
			VGA_VS_OUT <= out_vs;
			VGA_HBLANK_OUT <= out_hblank;
			VGA_VBLANK_OUT <= out_vblank;
		end
	end

endmodule
