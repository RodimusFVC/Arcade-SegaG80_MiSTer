// ============================================================================
// CRT profile resolver.
// written 2026 by Videodr0me
//
// Resolves the selected profile into the settings used by vfb_top.
// Fixed profiles vary by resolution; Custom 1 and Custom 2 use their
// editable OSD values.
// ============================================================================

module vfb_profile_resolver (
	input  logic [2:0]  profile,
	input  logic [11:0] fb_height,

	input  logic [2:0]  off_dot_mode,
	input  logic [1:0]  off_tonemapping,
	input  logic [1:0]  off_inter_frame_decay,
	input  logic [1:0]  off_intra_frame_decay,
	input  logic [29:0] custom1_settings,
	input  logic [29:0] custom2_settings,

	output logic [2:0]  dot_mode,
	output logic [1:0]  tonemapping,
	output logic [2:0]  bloom_width,
	output logic [2:0]  bloom_curve,
	output logic [2:0]  halo_filter,
	output logic [2:0]  halo_curve,
	output logic [1:0]  halo_spread,
	output logic [1:0]  halo_knee,
	output logic [1:0]  inter_frame_decay,
	output logic [1:0]  intra_frame_decay,
	output logic        color_space,
	output logic [2:0]  presentation_color,
	output logic        slot_mask,
	output logic        full_bypass
);

	localparam logic [2:0] PROFILE_OFF        = 3'd0;
	localparam logic [2:0] PROFILE_TOUCH      = 3'd1;
	localparam logic [2:0] PROFILE_TYPICAL    = 3'd2;
	localparam logic [2:0] PROFILE_OVERDRIVEN = 3'd3;
	localparam logic [2:0] PROFILE_NEON       = 3'd4;
	localparam logic [2:0] PROFILE_STRANGER   = 3'd5;
	localparam logic [2:0] PROFILE_CUSTOM1    = 3'd6;
	localparam logic [2:0] PROFILE_CUSTOM2    = 3'd7;

	localparam logic [2:0] DOT_2X  = 3'd0;
	localparam logic [2:0] DOT_25X = 3'd1;
	localparam logic [2:0] DOT_3X  = 3'd2;
	localparam logic [2:0] DOT_1X  = 3'd3;

	localparam logic [1:0] TONE_LINEAR1 = 2'd0;
	localparam logic [1:0] TONE_LINEAR2 = 2'd1;
	localparam logic [1:0] TONE_BRIGHT  = 2'd2;
	localparam logic [1:0] TONE_OFF     = 2'd3;

	localparam logic [2:0] BLOOM_OFF    = 3'd0;
	localparam logic [2:0] BLOOM_THIN   = 3'd1;
	localparam logic [2:0] BLOOM_TIGHT  = 3'd2;
	localparam logic [2:0] BLOOM_SOFT   = 3'd3;
	localparam logic [2:0] BLOOM_NORMAL = 3'd4;
	localparam logic [2:0] BLOOM_BROAD  = 3'd5;
	localparam logic [2:0] BLOOM_WIDE_M = 3'd6;
	localparam logic [2:0] BLOOM_WIDE   = 3'd7;

	localparam logic [2:0] CURVE_MINIMAL  = 3'd0;
	localparam logic [2:0] CURVE_MIN_PLUS = 3'd1;
	localparam logic [2:0] CURVE_MILD     = 3'd2;
	localparam logic [2:0] CURVE_MILD_P   = 3'd3;
	localparam logic [2:0] CURVE_MODERATE = 3'd4;
	localparam logic [2:0] CURVE_MOD_PLUS = 3'd5;
	localparam logic [2:0] CURVE_STRONG_M = 3'd6;
	localparam logic [2:0] CURVE_STRONG   = 3'd7;

	localparam logic [2:0] HALO_OFF  = 3'd0;
	localparam logic [2:0] HALO_025X = 3'd1;
	localparam logic [2:0] HALO_033X = 3'd2;
	localparam logic [2:0] HALO_050X = 3'd3;
	localparam logic [2:0] HALO_075X = 3'd4;
	localparam logic [2:0] HALO_100X = 3'd5;
	localparam logic [2:0] HALO_125X = 3'd6;
	localparam logic [2:0] HALO_150X = 3'd7;

	localparam logic [1:0] SPREAD_ORIGINAL = 2'd0;
	localparam logic [1:0] SPREAD_WIDE1    = 2'd1;
	localparam logic [1:0] SPREAD_WIDE2    = 2'd2;
	localparam logic [1:0] SPREAD_FOCUS    = 2'd3;

	localparam logic [1:0] KNEE_16  = 2'd0;
	localparam logic [1:0] KNEE_32  = 2'd1;
	localparam logic [1:0] KNEE_64  = 2'd2;
	localparam logic [1:0] KNEE_24  = 2'd3;

	localparam logic [1:0] INTER_OFF    = 2'd0;
	localparam logic [1:0] INTER_SHORT  = 2'd1;
	localparam logic [1:0] INTER_MEDIUM = 2'd2;
	localparam logic [1:0] INTER_LONG   = 2'd3;

	localparam logic [1:0] INTRA_OFF   = 2'd0;
	localparam logic [1:0] INTRA_LUT_A = 2'd1;
	localparam logic [1:0] INTRA_LUT_B = 2'd2;
	localparam logic [1:0] INTRA_LUT_C = 2'd3;

	localparam logic COLORSPACE_OFF    = 1'b0;
	localparam logic COLORSPACE_AMP709 = 1'b1;

	localparam logic [2:0] CHANNEL_ORIGINAL = 3'd0;

	localparam logic SLOT_MASK_OFF = 1'b0;
	localparam logic SLOT_MASK_ON  = 1'b1;

	function automatic logic [29:0] pack_settings;
		input logic [2:0] dot_i;
		input logic [1:0] tone_i;
		input logic [2:0] bloom_width_i;
		input logic [2:0] bloom_curve_i;
		input logic [2:0] halo_i;
		input logic [2:0] halo_curve_i;
		input logic [1:0] halo_spread_i;
		input logic [1:0] halo_knee_i;
		input logic [1:0] inter_decay_i;
		input logic [1:0] intra_decay_i;
		input logic       color_space_i;
		input logic [2:0] color_i;
		input logic       slot_mask_i;
		begin
			pack_settings = {
				halo_knee_i,
				halo_curve_i,
				dot_i,
				tone_i,
				bloom_width_i,
				bloom_curve_i,
				halo_i,
				halo_spread_i,
				inter_decay_i,
				intra_decay_i,
				color_space_i,
				color_i,
				slot_mask_i
			};
		end
	endfunction

	function automatic logic [29:0] fixed_480p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH: fixed_480p = pack_settings(
					DOT_2X, TONE_OFF, BLOOM_THIN, CURVE_MODERATE,
					HALO_025X, CURVE_MINIMAL, SPREAD_FOCUS, KNEE_64,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_TYPICAL: fixed_480p = pack_settings(
					DOT_2X, TONE_OFF, BLOOM_THIN, CURVE_MOD_PLUS,
					HALO_033X, CURVE_MINIMAL, SPREAD_ORIGINAL, KNEE_32,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_OVERDRIVEN: fixed_480p = pack_settings(
					DOT_25X, TONE_OFF, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_033X, CURVE_MILD_P, SPREAD_WIDE1, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_NEON: fixed_480p = pack_settings(
					DOT_3X, TONE_OFF, BLOOM_TIGHT, CURVE_MOD_PLUS,
					HALO_033X, CURVE_MODERATE, SPREAD_WIDE1, KNEE_32,
					INTER_MEDIUM, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_STRANGER: fixed_480p = pack_settings(
					DOT_3X, TONE_LINEAR1, BLOOM_SOFT, CURVE_MILD_P,
					HALO_050X, CURVE_MOD_PLUS, SPREAD_ORIGINAL, KNEE_24,
					INTER_MEDIUM, INTRA_LUT_B,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				default: fixed_480p = pack_settings(
					DOT_1X, TONE_LINEAR1, BLOOM_OFF, CURVE_MINIMAL,
					HALO_OFF, CURVE_MINIMAL, SPREAD_ORIGINAL, KNEE_16,
					INTER_OFF, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
			endcase
		end
	endfunction

	function automatic logic [29:0] fixed_720p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH: fixed_720p = pack_settings(
					DOT_25X, TONE_OFF, BLOOM_THIN, CURVE_STRONG,
					HALO_025X, CURVE_MIN_PLUS, SPREAD_WIDE1, KNEE_32,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_TYPICAL: fixed_720p = pack_settings(
					DOT_3X, TONE_OFF, BLOOM_TIGHT, CURVE_MOD_PLUS,
					HALO_033X, CURVE_MILD_P, SPREAD_WIDE1, KNEE_24,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_AMP709, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				PROFILE_OVERDRIVEN: fixed_720p = pack_settings(
					DOT_3X, TONE_LINEAR1, BLOOM_SOFT, CURVE_MILD,
					HALO_033X, CURVE_MODERATE, SPREAD_WIDE1, KNEE_32,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_AMP709, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				PROFILE_NEON: fixed_720p = pack_settings(
					DOT_3X, TONE_LINEAR1, BLOOM_NORMAL, CURVE_MILD,
					HALO_050X, CURVE_MODERATE, SPREAD_WIDE1, KNEE_32,
					INTER_MEDIUM, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_STRANGER: fixed_720p = pack_settings(
					DOT_3X, TONE_BRIGHT, BLOOM_SOFT, CURVE_MOD_PLUS,
					HALO_150X, CURVE_MODERATE, SPREAD_WIDE1, KNEE_16,
					INTER_LONG, INTRA_LUT_B,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				default: fixed_720p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	function automatic logic [29:0] fixed_1080p;
		input logic [2:0] profile_i;
		begin
			case (profile_i)
				PROFILE_TOUCH: fixed_1080p = pack_settings(
					DOT_3X, TONE_OFF, BLOOM_TIGHT, CURVE_MILD_P,
					HALO_033X, CURVE_MIN_PLUS, SPREAD_FOCUS, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_OFF);
				PROFILE_TYPICAL: fixed_1080p = pack_settings(
					DOT_3X, TONE_OFF, BLOOM_TIGHT, CURVE_MOD_PLUS,
					HALO_050X, CURVE_MILD, SPREAD_WIDE2, KNEE_16,
					INTER_SHORT, INTRA_OFF,
					COLORSPACE_AMP709, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				PROFILE_OVERDRIVEN: fixed_1080p = pack_settings(
					DOT_3X, TONE_LINEAR1, BLOOM_SOFT, CURVE_MILD_P,
					HALO_050X, CURVE_MILD, SPREAD_WIDE2, KNEE_24,
					INTER_MEDIUM, INTRA_OFF,
					COLORSPACE_AMP709, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				PROFILE_NEON: fixed_1080p = pack_settings(
					DOT_3X, TONE_LINEAR2, BLOOM_NORMAL, CURVE_MILD,
					HALO_050X, CURVE_MOD_PLUS, SPREAD_WIDE1, KNEE_32,
					INTER_MEDIUM, INTRA_LUT_A,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				PROFILE_STRANGER: fixed_1080p = pack_settings(
					DOT_3X, TONE_BRIGHT, BLOOM_BROAD, CURVE_MILD,
					HALO_150X, CURVE_MODERATE, SPREAD_WIDE1, KNEE_16,
					INTER_LONG, INTRA_LUT_B,
					COLORSPACE_OFF, CHANNEL_ORIGINAL, SLOT_MASK_ON);
				default: fixed_1080p = fixed_480p(profile_i);
			endcase
		end
	endfunction

	logic [29:0] selected_settings;

	always_comb begin
		unique case (profile)
			PROFILE_OFF: selected_settings = pack_settings(
				off_dot_mode, off_tonemapping, BLOOM_OFF, CURVE_MINIMAL,
				HALO_OFF, CURVE_MINIMAL, SPREAD_ORIGINAL, KNEE_16,
				off_inter_frame_decay,
				off_intra_frame_decay, COLORSPACE_OFF, CHANNEL_ORIGINAL,
				SLOT_MASK_OFF);
			PROFILE_CUSTOM1: selected_settings = custom1_settings;
			PROFILE_CUSTOM2: selected_settings = custom2_settings;
			default: begin
				if (fb_height >= 12'd1000)
					selected_settings = fixed_1080p(profile);
				else if (fb_height >= 12'd700)
					selected_settings = fixed_720p(profile);
				else
					selected_settings = fixed_480p(profile);
			end
		endcase

		dot_mode       = selected_settings[24:22];
		tonemapping    = selected_settings[21:20];
		bloom_width    = selected_settings[19:17];
		bloom_curve    = selected_settings[16:14];
		halo_filter    = selected_settings[13:11];
		halo_curve     = selected_settings[27:25];
		halo_spread    = selected_settings[10:9];
		halo_knee      = selected_settings[29:28];
		inter_frame_decay = selected_settings[8:7];
		intra_frame_decay = selected_settings[6:5];
		color_space    = selected_settings[4];
		presentation_color = selected_settings[3:1];
		slot_mask      = selected_settings[0];
		full_bypass    = (profile == PROFILE_OFF);
	end

endmodule
