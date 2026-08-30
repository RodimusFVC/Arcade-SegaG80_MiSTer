// ---------------------------------------------------------------------------
// svf.v -- Chamberlin state variable filter, one sample per `tick`.
//
// Stands in for the LM324 active filter sections on sheets 8 and 9. Each of
// those is a two-pole multiple-feedback section whose centre frequency is
// 1/(2*pi*C*sqrt(R_in*R_fb)) and whose Q is 0.5*sqrt(R_fb/R_in), so a single
// SVF per section reproduces both the corner and the resonance.
//
// F_Q16 = 2*pi*f0*65536/fs      (accurate while f0 << fs)
// Q_Q16 = 65536/Q
// ---------------------------------------------------------------------------

`default_nettype none

// This core is DSP-saturated; keep the board's multipliers in logic.
(* multstyle = "logic" *)
module svf #(
    parameter integer AUDIO_HZ = 48_000,
    parameter integer F0_HZ    = 500,
    parameter integer Q_X100   = 100          // Q * 100
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire signed [17:0] in,
    output wire signed [17:0] lp,
    output wire signed [17:0] bp,
    output wire signed [17:0] hp
);

    // 2*pi*65536 = 411775
    localparam [63:0] F_Q16 = (64'd411775 * F0_HZ) / AUDIO_HZ;
    localparam [63:0] Q_Q16 = (64'd6553600) / Q_X100;

    reg signed [23:0] s_lp, s_bp;

    wire signed [23:0] in_x  = {{6{in[17]}}, in};
    (* multstyle = "logic" *) wire signed [47:0] f_bp  = $signed(F_Q16[17:0]) * s_bp;
    (* multstyle = "logic" *) wire signed [47:0] q_bp  = $signed(Q_Q16[19:0]) * s_bp;

    wire signed [23:0] hp_i  = in_x - s_lp - q_bp[39:16];
    (* multstyle = "logic" *) wire signed [47:0] f_hp  = $signed(F_Q16[17:0]) * hp_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_lp <= 24'sd0;
            s_bp <= 24'sd0;
        end else if (tick) begin
            s_lp <= s_lp + f_bp[39:16];
            s_bp <= s_bp + f_hp[39:16];
        end
    end

    // saturate back to 18 bits
    function signed [17:0] sat18;
        input signed [23:0] x;
        begin
            if      (x >  24'sd131071) sat18 =  18'sd131071;
            else if (x < -24'sd131072) sat18 = -18'sd131072;
            else                       sat18 = x[17:0];
        end
    endfunction

    assign lp = sat18(s_lp);
    assign bp = sat18(s_bp);
    assign hp = sat18(hp_i);

endmodule

`default_nettype wire
