//============================================================================
//  TMS36XX — TI organ tone generator (TMS3615 / TMS3617)
//
//  RTL port of MAME's sound/tms36xx.cpp (BSD-3-Clause, Juergen Buchmueller).
//  Bit-exact with that model's integer arithmetic, not a netlist model of the
//  real chip — MAME's is the only public behavioural description, and it is
//  what makes Monster Bash's music recognisable.
//
//  Used by: Monster Bash (TMS3617, 6 outputs).  The TMS3615 (Naughty Boy,
//  Pleiads — 13 notes, one output) is the same datapath with the octave input
//  driven; leave voice_enable at 6'h3F for it.  The MM6221AA fixed-melody
//  variant (Phoenix) is NOT ported — it needs the three 96-note tune tables,
//  and no core here plays them.
//
//  How the model works
//  --------------------------------------------------------------------------
//  Twelve voice slots, two banks of six.  A note write shifts banks and
//  strikes all six harmonics of that note (16', 8', 5 1/3', 4', 2 2/3', 2')
//  at full volume; the previous bank is left to decay, so a new note never
//  cuts off the tail of the last one.  Each slot is a square-wave counter
//  plus a linear volume decay.
//
//  Note that MAME never calls set_tune_speed() for the TMS3617, so m_speed is
//  0.  Following that through sound_stream_update: the tune counter fires once
//  immediately after tms36xx_reset_counters() and then never again, so one
//  note write produces exactly ONE strike.  This module implements that
//  directly rather than reproducing the dead tune sequencer.
//
//  All twelve slots are walked by a sequencer, one per sample tick — at
//  15808 Hz on a 15.47 MHz clock there are ~978 cycles per sample and a pass
//  costs well under a hundred, so there is no reason to spend twelve copies of
//  the datapath.  Decay times below ~30 ms would not fit that budget.
//
//  MAME's stream output is unipolar (a sum of positive volumes), so the DC
//  blocker at the end stands in for the real board's coupling capacitor.
//============================================================================

`default_nettype none

module tms36xx #(
    parameter int unsigned CLK_HZ    = 15_468_480,  // system clock
    parameter int unsigned BASEFREQ  =        247,  // MAME device clock()
    // Decay times in ms, per harmonic. MAME takes seconds; 0 disables a voice.
    parameter int unsigned DECAY0_MS =        500,
    parameter int unsigned DECAY1_MS =        500,
    parameter int unsigned DECAY2_MS =        500,
    parameter int unsigned DECAY3_MS =        500,
    parameter int unsigned DECAY4_MS =        500,
    parameter int unsigned DECAY5_MS =        500
)(
    input  wire                clk,
    input  wire                reset,

    input  wire                note_we,       // strobe: strike a note
    input  wire         [1:0]  note_octave,   // TMS3615; 0 on Monster Bash
    input  wire         [3:0]  note,          // 0-12 valid, 13-15 ignored

    input  wire                enable_we,     // strobe: voice enable mask
    input  wire         [5:0]  voice_enable,

    output wire signed [15:0]  audio,
    output wire                ce_snd         // one pulse per output sample
);

    localparam int unsigned SAMPLERATE = BASEFREQ * 64;   // MAME: clock()*64
    localparam int unsigned VMAX       = 32767;

    localparam signed [25:0] SR_VOL  = 26'(SAMPLERATE);
    localparam signed [18:0] SR_TONE = 19'(SAMPLERATE);

    // MAME device_start: m_decay[j] = VMAX / decay_seconds
    localparam int unsigned DEC0 = (DECAY0_MS != 0) ? (VMAX * 1000) / DECAY0_MS : 0;
    localparam int unsigned DEC1 = (DECAY1_MS != 0) ? (VMAX * 1000) / DECAY1_MS : 0;
    localparam int unsigned DEC2 = (DECAY2_MS != 0) ? (VMAX * 1000) / DECAY2_MS : 0;
    localparam int unsigned DEC3 = (DECAY3_MS != 0) ? (VMAX * 1000) / DECAY3_MS : 0;
    localparam int unsigned DEC4 = (DECAY4_MS != 0) ? (VMAX * 1000) / DECAY4_MS : 0;
    localparam int unsigned DEC5 = (DECAY5_MS != 0) ? (VMAX * 1000) / DECAY5_MS : 0;

    // ...and the initial enable mask, one bit per harmonic with a decay set.
    localparam [5:0] INIT_EN = { DECAY5_MS != 0, DECAY4_MS != 0, DECAY3_MS != 0,
                                DECAY2_MS != 0, DECAY1_MS != 0, DECAY0_MS != 0 };

    //------------------------------------------------------------------------
    // Sample tick
    //------------------------------------------------------------------------
    localparam [32:0] ACC_INC = 33'((longint'(SAMPLERATE) <<< 32) / longint'(CLK_HZ));

    reg [32:0] ce_acc = '0;
    always @(posedge clk) ce_acc <= {1'b0, ce_acc[31:0]} + ACC_INC;
    wire smp_tick = ce_acc[32];

    //------------------------------------------------------------------------
    // tune4 — the 13 notes x 6 harmonics table, exactly as MAME builds it
    //------------------------------------------------------------------------
    function automatic [14:0] tune4 (input [6:0] idx);
        reg [14:0] t4;
        begin
            case (idx)
            7'd0 : t4 = 15'd1149 ;   // note  0, 16'
            7'd1 : t4 = 15'd2298 ;   // note  0, 8'
            7'd2 : t4 = 15'd2896 ;   // note  0, 5 1/3'
            7'd3 : t4 = 15'd4597 ;   // note  0, 4'
            7'd4 : t4 = 15'd5792 ;   // note  0, 2 2/3'
            7'd5 : t4 = 15'd9195 ;   // note  0, 2'
            7'd6 : t4 = 15'd1217 ;   // note  1, 16'
            7'd7 : t4 = 15'd2435 ;   // note  1, 8'
            7'd8 : t4 = 15'd3068 ;   // note  1, 5 1/3'
            7'd9 : t4 = 15'd4871 ;   // note  1, 4'
            7'd10: t4 = 15'd6137 ;   // note  1, 2 2/3'
            7'd11: t4 = 15'd9742 ;   // note  1, 2'
            7'd12: t4 = 15'd1290 ;   // note  2, 16'
            7'd13: t4 = 15'd2580 ;   // note  2, 8'
            7'd14: t4 = 15'd3250 ;   // note  2, 5 1/3'
            7'd15: t4 = 15'd5160 ;   // note  2, 4'
            7'd16: t4 = 15'd6501 ;   // note  2, 2 2/3'
            7'd17: t4 = 15'd10321;   // note  2, 2'
            7'd18: t4 = 15'd1366 ;   // note  3, 16'
            7'd19: t4 = 15'd2733 ;   // note  3, 8'
            7'd20: t4 = 15'd3444 ;   // note  3, 5 1/3'
            7'd21: t4 = 15'd5467 ;   // note  3, 4'
            7'd22: t4 = 15'd6888 ;   // note  3, 2 2/3'
            7'd23: t4 = 15'd10935;   // note  3, 2'
            7'd24: t4 = 15'd1448 ;   // note  4, 16'
            7'd25: t4 = 15'd2896 ;   // note  4, 8'
            7'd26: t4 = 15'd3649 ;   // note  4, 5 1/3'
            7'd27: t4 = 15'd5792 ;   // note  4, 4'
            7'd28: t4 = 15'd7298 ;   // note  4, 2 2/3'
            7'd29: t4 = 15'd11585;   // note  4, 2'
            7'd30: t4 = 15'd1534 ;   // note  5, 16'
            7'd31: t4 = 15'd3068 ;   // note  5, 8'
            7'd32: t4 = 15'd3866 ;   // note  5, 5 1/3'
            7'd33: t4 = 15'd6137 ;   // note  5, 4'
            7'd34: t4 = 15'd7732 ;   // note  5, 2 2/3'
            7'd35: t4 = 15'd12274;   // note  5, 2'
            7'd36: t4 = 15'd1625 ;   // note  6, 16'
            7'd37: t4 = 15'd3250 ;   // note  6, 8'
            7'd38: t4 = 15'd4096 ;   // note  6, 5 1/3'
            7'd39: t4 = 15'd6501 ;   // note  6, 4'
            7'd40: t4 = 15'd8192 ;   // note  6, 2 2/3'
            7'd41: t4 = 15'd13003;   // note  6, 2'
            7'd42: t4 = 15'd1722 ;   // note  7, 16'
            7'd43: t4 = 15'd3444 ;   // note  7, 8'
            7'd44: t4 = 15'd4339 ;   // note  7, 5 1/3'
            7'd45: t4 = 15'd6888 ;   // note  7, 4'
            7'd46: t4 = 15'd8679 ;   // note  7, 2 2/3'
            7'd47: t4 = 15'd13777;   // note  7, 2'
            7'd48: t4 = 15'd1824 ;   // note  8, 16'
            7'd49: t4 = 15'd3649 ;   // note  8, 8'
            7'd50: t4 = 15'd4597 ;   // note  8, 5 1/3'
            7'd51: t4 = 15'd7298 ;   // note  8, 4'
            7'd52: t4 = 15'd9195 ;   // note  8, 2 2/3'
            7'd53: t4 = 15'd14596;   // note  8, 2'
            7'd54: t4 = 15'd1933 ;   // note  9, 16'
            7'd55: t4 = 15'd3866 ;   // note  9, 8'
            7'd56: t4 = 15'd4871 ;   // note  9, 5 1/3'
            7'd57: t4 = 15'd7732 ;   // note  9, 4'
            7'd58: t4 = 15'd9742 ;   // note  9, 2 2/3'
            7'd59: t4 = 15'd15464;   // note  9, 2'
            7'd60: t4 = 15'd2048 ;   // note 10, 16'
            7'd61: t4 = 15'd4096 ;   // note 10, 8'
            7'd62: t4 = 15'd5160 ;   // note 10, 5 1/3'
            7'd63: t4 = 15'd8192 ;   // note 10, 4'
            7'd64: t4 = 15'd10321;   // note 10, 2 2/3'
            7'd65: t4 = 15'd16384;   // note 10, 2'
            7'd66: t4 = 15'd2169 ;   // note 11, 16'
            7'd67: t4 = 15'd4339 ;   // note 11, 8'
            7'd68: t4 = 15'd5467 ;   // note 11, 5 1/3'
            7'd69: t4 = 15'd8679 ;   // note 11, 4'
            7'd70: t4 = 15'd10935;   // note 11, 2 2/3'
            7'd71: t4 = 15'd17358;   // note 11, 2'
            7'd72: t4 = 15'd2298 ;   // note 12, 16'
            7'd73: t4 = 15'd4597 ;   // note 12, 8'
            7'd74: t4 = 15'd5792 ;   // note 12, 5 1/3'
            7'd75: t4 = 15'd9195 ;   // note 12, 4'
            7'd76: t4 = 15'd11585;   // note 12, 2 2/3'
            7'd77: t4 = 15'd18390;   // note 12, 2'
            default: t4 = 15'd0;
            endcase
            tune4 = t4;
        end
    endfunction

    // Per-harmonic decay rate. MAME sets m_decay[j] == m_decay[j+6], so the
    // two banks share it.
    function automatic [25:0] decay_of (input [3:0] v);
        reg [2:0] h;
        begin
            h = (v >= 4'd6) ? (v[2:0] - 3'd6) : v[2:0];
            case (h)
                3'd0:    decay_of = 26'(DEC0);
                3'd1:    decay_of = 26'(DEC1);
                3'd2:    decay_of = 26'(DEC2);
                3'd3:    decay_of = 26'(DEC3);
                3'd4:    decay_of = 26'(DEC4);
                default: decay_of = 26'(DEC5);
            endcase
        end
    endfunction

    // 32768/n, so a divide by m_voices (== 2n) becomes one multiply.
    function automatic [15:0] recip_of (input [2:0] n);
        begin
            case (n)
                3'd1:    recip_of = 16'd32768;
                3'd2:    recip_of = 16'd16384;
                3'd3:    recip_of = 16'd10922;
                3'd4:    recip_of = 16'd8192;
                3'd5:    recip_of = 16'd6553;
                3'd6:    recip_of = 16'd5461;
                default: recip_of = 16'd0;
            endcase
        end
    endfunction

    //------------------------------------------------------------------------
    // Voice state — twelve slots, two banks of six
    //------------------------------------------------------------------------
    reg        [15:0] vol  [0:11];
    reg signed [25:0] volc [0:11];
    reg        [15:0] freq [0:11];
    reg signed [18:0] cnt  [0:11];
    reg        [11:0] outbit;

    reg        [11:0] en12;
    reg         [2:0] nvoices;      // enabled harmonics; MAME's m_voices == 2x
    reg               bank;         // MAME's m_shift, 0 or 6

    // Pending work
    reg               smp_pend;
    reg               note_pend;
    reg         [3:0] note_r;
    reg         [1:0] oct_r;

    wire        [2:0] popcnt = 3'(voice_enable[0]) + 3'(voice_enable[1])
                             + 3'(voice_enable[2]) + 3'(voice_enable[3])
                             + 3'(voice_enable[4]) + 3'(voice_enable[5]);

    //------------------------------------------------------------------------
    // Sequencer. MAME's per-sample order is: decay all twelve, advance the
    // tune (the strike), then tone all twelve. Kept in that order.
    //------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0, S_DEC0 = 3'd1, S_DECL = 3'd2, S_STRIKE = 3'd3,
                     S_RST  = 3'd4, S_TON0 = 3'd5, S_TONL = 3'd6, S_FIN = 3'd7;

    reg  [2:0] state;
    reg  [3:0] v;
    reg  [2:0] j;
    reg [20:0] sum;

    // Strike frequency: tune4 * (basefreq << octave) / FSCALE, MAME's order of
    // operations — the shift happens before the truncating divide.
    wire [14:0] t4_val  = tune4(7'(note_r) * 7'd6 + 7'(j));
    wire [45:0] f_prod  = (46'(t4_val) * 46'(BASEFREQ)) << oct_r;
    wire [15:0] f_new   = 16'(f_prod >> 10);

    wire [3:0]  slot    = bank ? (4'd6 + 4'(j)) : 4'(j);
    wire [25:0] dec_v   = decay_of(v);   // no bit-select on a call
    wire [3:0]  nxt_v   = v + 4'd1;

    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 12; i = i + 1) begin
                vol[i]  <= 16'd0;
                volc[i] <= 26'sd0;
                freq[i] <= 16'd0;
                cnt[i]  <= 19'sd0;
            end
            outbit    <= 12'd0;
            en12      <= {INIT_EN, INIT_EN};   // MAME device_start
            nvoices   <= 3'(INIT_EN[0]) + 3'(INIT_EN[1]) + 3'(INIT_EN[2])
                       + 3'(INIT_EN[3]) + 3'(INIT_EN[4]) + 3'(INIT_EN[5]);
            bank      <= 1'b0;
            smp_pend  <= 1'b0;
            note_pend <= 1'b0;
            note_r    <= 4'd0;
            oct_r     <= 2'd0;
            state     <= S_IDLE;
            v         <= 4'd0;
            j         <= 3'd0;
            sum       <= 21'd0;
        end else begin
            if (smp_tick)  smp_pend <= 1'b1;

            // tms36xx_note_w: notes above 12 change nothing at all
            if (note_we && (note <= 4'd12)) begin
                note_pend <= 1'b1;
                note_r    <= note;
                oct_r     <= note_octave;
            end

            // tms3617_enable_w
            if (enable_we) begin
                en12    <= {voice_enable, voice_enable};
                nvoices <= popcnt;
            end

            case (state)
            S_IDLE:
                if (smp_pend) begin
                    smp_pend <= 1'b0;
                    v        <= 4'd0;
                    state    <= S_DEC0;
                end

            // ---- DECAY(v) -----------------------------------------------
            S_DEC0:
                if (vol[v] != 16'd0) begin
                    volc[v] <= volc[v] - $signed({1'b0, dec_v[24:0]});
                    state   <= S_DECL;
                end else begin
                    v     <= nxt_v;
                    state <= (nxt_v == 4'd12) ? S_STRIKE : S_DEC0;
                end

            S_DECL:
                if (volc[v] <= 26'sd0) begin
                    volc[v] <= volc[v] + SR_VOL;
                    if (vol[v] == 16'd0) begin
                        freq[v] <= 16'd0;      // MAME: vol-- <= VMIN, then break
                        v       <= nxt_v;
                        state   <= (nxt_v == 4'd12) ? S_STRIKE : S_DEC0;
                    end else begin
                        vol[v] <= vol[v] - 16'd1;
                    end
                end else begin
                    v     <= nxt_v;
                    state <= (nxt_v == 4'd12) ? S_STRIKE : S_DEC0;
                end

            // ---- the strike: reset counters, flip bank, restart six -------
            S_STRIKE:
                if (note_pend) begin
                    note_pend <= 1'b0;
                    for (i = 0; i < 12; i = i + 1) begin
                        volc[i] <= 26'sd0;     // tms36xx_reset_counters
                        cnt[i]  <= 19'sd0;
                    end
                    bank  <= ~bank;
                    j     <= 3'd0;
                    state <= S_RST;
                end else begin
                    v     <= 4'd0;
                    sum   <= 21'd0;
                    state <= S_TON0;
                end

            S_RST: begin
                // Every tune4 entry is non-zero, so RESTART always fires.
                freq[slot] <= f_new;
                vol[slot]  <= 16'(VMAX);
                j          <= j + 3'd1;
                if (j == 3'd5) begin
                    v     <= 4'd0;
                    sum   <= 21'd0;
                    state <= S_TON0;
                end
            end

            // ---- TONE(v) -------------------------------------------------
            S_TON0:
                if (en12[v] && (freq[v] != 16'd0)) begin
                    cnt[v] <= cnt[v] - $signed({3'b0, freq[v]});
                    state  <= S_TONL;
                end else begin
                    v     <= nxt_v;
                    state <= (nxt_v == 4'd12) ? S_FIN : S_TON0;
                end

            S_TONL:
                if (cnt[v] <= 19'sd0) begin
                    cnt[v]     <= cnt[v] + SR_TONE;
                    outbit[v]  <= ~outbit[v];
                end else begin
                    if (outbit[v] && en12[v]) sum <= sum + 21'(vol[v]);
                    v     <= nxt_v;
                    state <= (nxt_v == 4'd12) ? S_FIN : S_TON0;
                end

            S_FIN:
                state <= S_IDLE;

            default: state <= S_IDLE;
            endcase
        end
    end

    //------------------------------------------------------------------------
    // Output. MAME normalises by 32768 * m_voices, i.e. sum / m_voices.
    //------------------------------------------------------------------------
    wire [36:0] scaled = 37'(sum) * 37'(recip_of(nvoices));
    wire [15:0] level  = (scaled[36:32] != 5'd0) ? 16'hFFFF : scaled[31:16];

    // The stream is unipolar; this stands in for the board's coupling cap.
    reg signed [31:0] dc_acc;
    reg signed [15:0] audio_r;
    reg               ce_r;

    wire signed [31:0] lvl_q8 = $signed({8'd0, level, 8'd0});
    wire signed [31:0] hp     = $signed({16'd0, level}) - $signed({{8{dc_acc[31]}}, dc_acc[31:8]});

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dc_acc  <= 32'sd0;
            audio_r <= 16'sd0;
            ce_r    <= 1'b0;
        end else begin
            ce_r <= (state == S_FIN);
            if (state == S_FIN) begin
                dc_acc  <= dc_acc + ((lvl_q8 - dc_acc) >>> 11);
                audio_r <= (hp >  32'sd32767) ?  16'sd32767 :
                           (hp < -32'sd32768) ? -16'sd32768 : hp[15:0];
            end
        end
    end

    assign audio  = audio_r;
    assign ce_snd = ce_r;

endmodule

`default_nettype wire
