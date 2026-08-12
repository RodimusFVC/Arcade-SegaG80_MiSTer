`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1, we = 0, addr = 0, ce = 1;
    reg [7:0] din = 8'hFF;
    wire signed [15:0] aout;

    astrob_audio dut(.clk_sys(clk), .reset(reset), .audio_we(we),
                     .audio_addr(addr), .audio_din(din), .ce_cpu(ce),
                     .audio_out(aout));

    always #32 clk = ~clk;   // ~15.5 MHz

    integer pk_pos, pk_neg, n_nonzero, i;
    integer inv2_min, inv2_max;

    task wr(input a, input [7:0] d);
    begin
        @(posedge clk); addr <= a; din <= d; we <= 1;
        @(posedge clk); we <= 0;
    end
    endtask

    initial begin
        pk_pos = 0; pk_neg = 0; n_nonzero = 0;
        inv2_min = 99999; inv2_max = -99999;
        repeat (10) @(posedge clk);
        reset = 0;
        repeat (10) @(posedge clk);

        // ---- all voices gated off, mute asserted (power-up state) ----
        repeat (2000) @(posedge clk);
        if (aout !== 16'sd0) $display("FAIL: not silent at power-up (%0d)", aout);
        else                 $display("PASS: silent at power-up");

        // ---- enable all four invaders, clear mute ----
        // $3E: bits0-3 low = invaders run, bit5 low = unmute, bit7 low = no warp
        wr(1'b0, 8'b1101_0000);
        // $3F: bit4 low = attack oscillator running, bit5 high = no rate reset
        wr(1'b1, 8'b1110_1111);

        // settle, then measure over ~40 ms
        repeat (20000) @(posedge clk);
        for (i = 0; i < 1200000; i = i + 1) begin
            @(posedge clk);
            if (aout > pk_pos) pk_pos = aout;
            if (aout < pk_neg) pk_neg = aout;
            if (aout !== 0) n_nonzero = n_nonzero + 1;
        end
        $display("mix peaks: +%0d / %0d   nonzero samples: %0d", pk_pos, pk_neg, n_nonzero);
        if (pk_pos > 10000 && pk_pos < 20000) $display("PASS: peak in expected ~14.4k band");
        else                                   $display("FAIL: peak out of band");

        // ---- INV2 DAC staircase levels ----
        inv2_min = 99999; inv2_max = -99999;
        for (i = 0; i < 400000; i = i + 1) begin
            @(posedge clk);
            if (dut.inv2_out < inv2_min) inv2_min = dut.inv2_out;
            if (dut.inv2_out > inv2_max) inv2_max = dut.inv2_out;
        end
        $display("inv2_out range: %0d .. %0d (expect -6000..+6000)", inv2_min, inv2_max);
        if (inv2_max <= 6000 && inv2_min >= -6000 && inv2_max > 5000)
             $display("PASS: inv2 normalised to VOICE_FS");
        else $display("FAIL: inv2 range wrong");

        // ---- V staircase advances ----
        $display("vstep now = %0d", dut.vstep);

        // ---- mute ----
        wr(1'b0, 8'b1111_0000);   // bit5 high = mute
        repeat (100) @(posedge clk);
        if (aout === 16'sd0) $display("PASS: mute silences output");
        else                 $display("FAIL: mute did not silence (%0d)", aout);

        $finish;
    end
endmodule
