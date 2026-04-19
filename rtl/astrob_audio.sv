//============================================================================
//
//  Astro Blaster audio — simplified placeholder (NOT netlist-accurate)
//
//  Replaces MAME's nl_astrob netlist with three synthetic channels keyed
//  off the port $3E / $3F trigger latches. Intended to prove the audio
//  path to MiSTer HDMI, not to sound like the real arcade board.
//
//============================================================================

module astrob_audio (
    input                     clk_sys,
    input                     reset,

    // Z80 writes to ports $3E (addr=0) / $3F (addr=1)
    input                     audio_we,
    input                     audio_addr,     // 0 = $3E, 1 = $3F
    input               [7:0] audio_din,
    input                     ce_cpu,

    output reg signed  [15:0] audio_out
);

    //------------------------------------------------------------------------
    // Latches
    //------------------------------------------------------------------------
    reg [7:0] latch_3e, latch_3f;
    reg [7:0] prev_3e, prev_3f;
    reg [7:0] trig_3e, trig_3f;    // one-shot pulses on falling edges

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            latch_3e <= 8'hFF;
            latch_3f <= 8'hFF;
            prev_3e  <= 8'hFF;
            prev_3f  <= 8'hFF;
            trig_3e  <= 8'h00;
            trig_3f  <= 8'h00;
        end else begin
            trig_3e <= 8'h00;
            trig_3f <= 8'h00;
            if (audio_we & ce_cpu) begin
                if (audio_addr == 1'b0) begin
                    latch_3e <= audio_din;
                    prev_3e  <= latch_3e;
                    trig_3e  <= latch_3e & ~audio_din;   // falling edges
                end else begin
                    latch_3f <= audio_din;
                    prev_3f  <= latch_3f;
                    trig_3f  <= latch_3f & ~audio_din;
                end
            end
        end
    end

//    wire sound_on = ~latch_3f[6];
    wire sound_on = 1'b1;

    //------------------------------------------------------------------------
    // CH0 — TONE (square wave, freq selected by most-recent trigger)
    //------------------------------------------------------------------------
    reg [15:0] tone_div;    // clk_sys / (2*tone_div) = tone freq
    reg [15:0] tone_cnt;
    reg        tone_out;
    reg [15:0] tone_env;    // decay envelope

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            tone_div <= 16'd0;
            tone_cnt <= 16'd0;
            tone_out <= 1'b0;
            tone_env <= 16'd0;
        end else begin
            // Trigger & pitch select (approximate)
            // Invader steps: 440/494/587/659 Hz  →  divs @ 15.468 MHz
            //   440 Hz: 17578   494 Hz: 15660   587 Hz: 13177   659 Hz: 11731
            // Warp:  1 kHz swept — use 7734 as anchor
            // Bonus: 880 Hz (8789)
            // Sonar: 220 Hz (35154)
            if      (trig_3e[0]) begin tone_div <= 16'd17578; tone_env <= 16'hFFFF; end
            else if (trig_3e[1]) begin tone_div <= 16'd15660; tone_env <= 16'hFFFF; end
            else if (trig_3e[2]) begin tone_div <= 16'd13177; tone_env <= 16'hFFFF; end
            else if (trig_3e[3]) begin tone_div <= 16'd11731; tone_env <= 16'hFFFF; end
            else if (trig_3e[6]) begin tone_div <= 16'd7734;  tone_env <= 16'hFFFF; end
            else if (trig_3f[4]) begin tone_div <= 16'd8789;  tone_env <= 16'hFFFF; end
            else if (trig_3f[5]) begin tone_div <= 16'd35154; tone_env <= 16'hFFFF; end
            else if (tone_env != 16'd0) tone_env <= tone_env - 16'd1;

            if (tone_div != 16'd0) begin
                if (tone_cnt == 16'd0) begin
                    tone_cnt <= tone_div;
                    tone_out <= ~tone_out;
                end else begin
                    tone_cnt <= tone_cnt - 16'd1;
                end
            end
        end
    end

    //------------------------------------------------------------------------
    // CH1 — NOISE (Galois LFSR, triggered with decay envelope)
    //------------------------------------------------------------------------
    reg [17:0] lfsr;
    reg [15:0] noise_env;
    reg [ 7:0] noise_clk_div, noise_clk_cnt;
    reg        noise_out;

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            lfsr          <= 18'h3FFFF;
            noise_env     <= 16'd0;
            noise_clk_div <= 8'd100;   // ~155 kHz noise clock
            noise_clk_cnt <= 8'd0;
            noise_out     <= 1'b0;
        end else begin
            if (trig_3e[4] | trig_3e[5])           // asteroid / refill
                noise_env <= 16'hFFFF;
            else if (trig_3f[0])                   // short expl
                noise_env <= 16'h8000;
            else if (trig_3f[1])                   // long expl
                noise_env <= 16'hFFFF;
            else if (noise_env != 16'd0)
                noise_env <= noise_env - 16'd1;

            if (noise_clk_cnt == 8'd0) begin
                noise_clk_cnt <= noise_clk_div;
                lfsr          <= {lfsr[16:0], lfsr[17] ^ lfsr[10]};
                noise_out     <= lfsr[17];
            end else begin
                noise_clk_cnt <= noise_clk_cnt - 8'd1;
            end
        end
    end

    //------------------------------------------------------------------------
    // CH2 — LASER (swept square, freq sweeps down)
    //------------------------------------------------------------------------
    reg [15:0] laser_div;
    reg [15:0] laser_cnt;
    reg [13:0] laser_sweep_cnt;
    reg        laser_out;
    reg [15:0] laser_env;

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            laser_div        <= 16'd0;
            laser_cnt        <= 16'd0;
            laser_sweep_cnt  <= 14'd0;
            laser_out        <= 1'b0;
            laser_env        <= 16'd0;
        end else begin
            if (trig_3e[7]) begin
                laser_div       <= 16'd2000;    // start ~3.8 kHz
                laser_env       <= 16'hFFFF;
                laser_sweep_cnt <= 14'd0;
            end

            if (laser_env != 16'd0) begin
                // Every ~400 µs, bump divisor upward (pitch bend down)
                laser_sweep_cnt <= laser_sweep_cnt + 14'd1;
                if (laser_sweep_cnt == 14'd6000) begin
                    laser_sweep_cnt <= 14'd0;
                    laser_div       <= laser_div + 16'd100;
                end
                laser_env <= laser_env - 16'd1;

                if (laser_cnt == 16'd0) begin
                    laser_cnt <= laser_div;
                    laser_out <= ~laser_out;
                end else begin
                    laser_cnt <= laser_cnt - 16'd1;
                end
            end
        end
    end

    //------------------------------------------------------------------------
    // Mix
    //------------------------------------------------------------------------
    wire signed [15:0] s_tone  = (tone_out  ? 16'sd6000  : -16'sd6000);
    wire signed [15:0] s_noise = (noise_out ? 16'sd4000  : -16'sd4000);
    wire signed [15:0] s_laser = (laser_out ? 16'sd8000  : -16'sd8000);

    // Scale each by its envelope (top 8 bits of env → 0..255/256).
    wire signed [23:0] m_tone  = s_tone  * $signed({1'b0, tone_env[15:8]});
    wire signed [23:0] m_noise = s_noise * $signed({1'b0, noise_env[15:8]});
    wire signed [23:0] m_laser = s_laser * $signed({1'b0, laser_env[15:8]});

    wire signed [17:0] sum     = $signed(m_tone[23:8]) +
                                 $signed(m_noise[23:8]) +
                                 $signed(m_laser[23:8]);

    // Clamp to int16
    wire signed [15:0] clamped =
        (sum >  18'sd32767)   ?  16'sd32767 :
        (sum < -18'sd32768)   ? -16'sd32768 :
                                 sum[15:0];

    always @(posedge clk_sys or posedge reset) begin
        if (reset)
            audio_out <= 16'sd0;
        else
            audio_out <= sound_on ? clamped : 16'sd0;
    end

endmodule
