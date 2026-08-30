// ---------------------------------------------------------------------------
// tb_sega005.v -- drives the board the way the 005 program does.
//   iverilog -g2005 -o tb sim/tb_sega005.v rtl/*.v && ./tb
// Writes audio.txt: one decimal sample per line at AUDIO_HZ.
// ---------------------------------------------------------------------------

`timescale 1ns/1ns

module tb_sega005;

    localparam integer CLK_HZ   = 6_250_000;   // low, so Icarus finishes quickly
    localparam integer AUDIO_HZ = 48_000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #80 clk = ~clk;          // 6.25 MHz

    reg        cs_n = 1'b1, wr_n = 1'b1, rd_n = 1'b1;
    reg  [1:0] a    = 2'd0;
    reg  [7:0] d    = 8'hFF;
    wire [7:0] dout;
    wire signed [15:0] audio;
    wire pwm;

    sega005_sound #(
        .CLK_HZ(CLK_HZ),
        .ROM_FILE("epr-1286.hex"),
        .PROM_FILE("pr-5001.hex")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cs_n(cs_n), .wr_n(wr_n), .rd_n(rd_n),
        .cpu_addr(a), .cpu_din(d), .cpu_dout(dout),
        .audio(audio), .audio_pwm(pwm)
    );

    task ppi_write(input [1:0] port, input [7:0] val);
        begin
            @(negedge clk); a = port; d = val; cs_n = 1'b0; wr_n = 1'b0;
            @(posedge clk);
            @(negedge clk); wr_n = 1'b1; cs_n = 1'b1;
            @(posedge clk);
        end
    endtask

    integer fh;
    integer n;

    initial begin
        fh = $fopen("audio.txt", "w");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        // Mode 0, port A and B as outputs
        ppi_write(2'd3, 8'h80);

        // Port A idles high: every voice off
        ppi_write(2'd0, 8'hFF);

        // Port B: hold the sequencer in reset, then release it in auto mode
        // on ROM page 0.  bit4 = hold, bit5 = auto
        ppi_write(2'd1, 8'h10);
        ppi_write(2'd1, 8'h20);

        // Let the tune run on its own
        #300_000_000;                    // 400 ms

        // Whistle on (PA6 low), then off
        ppi_write(2'd0, 8'hBF);
        #500_000_000;
        ppi_write(2'd0, 8'hFF);
        #200_000_000;

        // Pistol shot, then small explosion
        ppi_write(2'd0, 8'hF7); ppi_write(2'd0, 8'hFF);
        #300_000_000;
        ppi_write(2'd0, 8'hFD); ppi_write(2'd0, 8'hFF);
        #300_000_000;

        // Large explosion
        ppi_write(2'd0, 8'hFE); ppi_write(2'd0, 8'hFF);
        #500_000_000;

        // Missile
        ppi_write(2'd0, 8'hEF); ppi_write(2'd0, 8'hFF);
        #300_000_000;

        // Bomb drop, the falling whistle
        ppi_write(2'd0, 8'hFB); ppi_write(2'd0, 8'hFF);
        #1_000_000_000;

        // Helicopter, held on
        ppi_write(2'd0, 8'hDF);
        #500_000_000;
        ppi_write(2'd0, 8'hFF);
        #300_000_000;

        $fclose(fh);
        $display("tb: wrote %0d samples to audio.txt", n);
        $finish;
    end

    // Sample the mixer output at AUDIO_HZ
    integer div = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            div <= 0;
            n   <= 0;
        end else if (div >= (CLK_HZ / AUDIO_HZ) - 1) begin
            div <= 0;
            $fwrite(fh, "%0d\n", audio);
            n   <= n + 1;
        end else begin
            div <= div + 1;
        end
    end

endmodule
