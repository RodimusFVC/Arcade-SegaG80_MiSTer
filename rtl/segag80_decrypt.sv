//============================================================================
//
//  Sega G-80 security chip decryption
//  MAME segag80_m.cpp:16-314
//
//  Six 315-00xx security chips share four sub-functions A/B/C/D selected
//  by 2 bits of the scrambled-write PC.
//
//============================================================================

module segag80_decrypt (
    input      [15:0] pc,
    input       [7:0] lo_in,
    input       [2:0] chip_sel,   // 0=noop, 1=62, 2=63, 3=64, 4=70, 5=76, 6=82
    output reg  [7:0] lo_out
);

    // Sub-functions (combinational)
    function [7:0] fn_A; input [7:0] b; fn_A = b; endfunction

    function [7:0] fn_B;
        input [7:0] b;
        fn_B = (b & 8'h03) | ((b & 8'h80) >> 1) | ((b & 8'h60) >> 3) |
               ((~b) & 8'h10) | ((b & 8'h08) << 2) | ((b & 8'h04) << 5);
    endfunction

    function [7:0] fn_C;
        input [7:0] b;
        fn_C = (b & 8'h03) | ((b & 8'h80) >> 4) | (((~b) & 8'h40) >> 1) |
               ((b & 8'h20) >> 1) | ((b & 8'h10) >> 2) |
               ((b & 8'h08) << 3) | ((b & 8'h04) << 5);
    endfunction

    function [7:0] fn_D;
        input [7:0] b;
        fn_D = (b & 8'h23) | ((b & 8'hC0) >> 4) | ((b & 8'h10) << 2) |
               ((b & 8'h08) << 1) | (((~b) & 8'h04) << 5);
    endfunction

    // Per-chip dispatch
    reg [7:0] s62, s63, s64, s70, s76, s82;

    always @* begin
        // 62: pc & 0x03  → 0:D 1:C 2:B 3:A
        case (pc & 16'h0003)
            16'h0000: s62 = fn_D(lo_in);
            16'h0001: s62 = fn_C(lo_in);
            16'h0002: s62 = fn_B(lo_in);
            16'h0003: s62 = fn_A(lo_in);
            default:  s62 = lo_in;
        endcase

        // 63: pc & 0x09  → 0:D 1:C 8:B 9:A  (others impossible)
        case (pc & 16'h0009)
            16'h0000: s63 = fn_D(lo_in);
            16'h0001: s63 = fn_C(lo_in);
            16'h0008: s63 = fn_B(lo_in);
            16'h0009: s63 = fn_A(lo_in);
            default:  s63 = lo_in;
        endcase

        // 64: pc & 0x03  → 0:A 1:B 2:C 3:D
        case (pc & 16'h0003)
            16'h0000: s64 = fn_A(lo_in);
            16'h0001: s64 = fn_B(lo_in);
            16'h0002: s64 = fn_C(lo_in);
            16'h0003: s64 = fn_D(lo_in);
            default:  s64 = lo_in;
        endcase

        // 70: pc & 0x09  → 0:B 1:A 8:D 9:C
        case (pc & 16'h0009)
            16'h0000: s70 = fn_B(lo_in);
            16'h0001: s70 = fn_A(lo_in);
            16'h0008: s70 = fn_D(lo_in);
            16'h0009: s70 = fn_C(lo_in);
            default:  s70 = lo_in;
        endcase

        // 76: pc & 0x09  → 0:A 1:B 8:C 9:D
        case (pc & 16'h0009)
            16'h0000: s76 = fn_A(lo_in);
            16'h0001: s76 = fn_B(lo_in);
            16'h0008: s76 = fn_C(lo_in);
            16'h0009: s76 = fn_D(lo_in);
            default:  s76 = lo_in;
        endcase

        // 82: pc & 0x11  → 0:A 1:B 10:C 11:D
        case (pc & 16'h0011)
            16'h0000: s82 = fn_A(lo_in);
            16'h0001: s82 = fn_B(lo_in);
            16'h0010: s82 = fn_C(lo_in);
            16'h0011: s82 = fn_D(lo_in);
            default:  s82 = lo_in;
        endcase

        // Chip select
        case (chip_sel)
            3'd1:    lo_out = s62;
            3'd2:    lo_out = s63;
            3'd3:    lo_out = s64;
            3'd4:    lo_out = s70;
            3'd5:    lo_out = s76;
            3'd6:    lo_out = s82;
            default: lo_out = lo_in;    // no-op
        endcase
    end

endmodule
