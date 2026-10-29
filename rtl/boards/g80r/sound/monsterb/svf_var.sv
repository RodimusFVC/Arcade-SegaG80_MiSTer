// ---------------------------------------------------------------------------
// svf_var.v -- Chamberlin state variable filter with run-time F and Q.
//
// Same core as 005/svf.sv, but the coefficients are inputs instead of
// parameters.  Monster Bash needs this because Q1 switches the shunt leg of
// the U3 filter under envelope control, moving f0 between two decades.
//
//   f_coef = 2*pi*f0*65536/fs      (accurate while f0 << fs)
//   q_coef = 65536/Q
// ---------------------------------------------------------------------------

`default_nettype none

// This core is DSP-saturated; keep the board's multipliers in logic.
(* multstyle = "logic" *)
module svf_var (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire        [17:0] f_coef,
    input  wire        [19:0] q_coef,
    input  wire signed [17:0] in,
    output wire signed [17:0] lp,
    output wire signed [17:0] bp,
    output wire signed [17:0] hp
);

    reg signed [23:0] s_lp, s_bp;

    wire signed [23:0] in_x = {{6{in[17]}}, in};

    (* multstyle = "logic" *) wire signed [47:0] f_bp = $signed({1'b0, f_coef}) * s_bp;
    (* multstyle = "logic" *) wire signed [47:0] q_bp = $signed({1'b0, q_coef}) * s_bp;

    wire signed [23:0] hp_i = in_x - s_lp - q_bp[39:16];

    (* multstyle = "logic" *) wire signed [47:0] f_hp = $signed({1'b0, f_coef}) * hp_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_lp <= 24'sd0;
            s_bp <= 24'sd0;
        end else if (tick) begin
            s_lp <= s_lp + f_bp[39:16];
            s_bp <= s_bp + f_hp[39:16];
        end
    end

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
