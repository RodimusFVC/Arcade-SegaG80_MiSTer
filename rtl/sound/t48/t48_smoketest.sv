// Minimal instantiation to verify the T48 (MCS-48) core compiles in-tree.
// Not referenced by the rest of the design; exists for Quartus compile regression.
module t48_smoketest (
    input  clk,
    output dummy
);
    t8039_notri #(.gate_port_input_g(0)) u_t8039 (
        .xtal_i        (clk),
        .xtal_en_i     (1'b1),
        .reset_n_i     (1'b0),
        .t0_i          (1'b0),
        .t0_o          (),
        .t0_dir_o      (),
        .int_n_i       (1'b1),
        .ea_i          (1'b1),
        .rd_n_o        (),
        .psen_n_o      (),
        .wr_n_o        (),
        .ale_o         (),
        .db_i          (8'h00),
        .db_o          (),
        .db_dir_o      (),
        .t1_i          (1'b0),
        .p2_i          (8'hFF),
        .p2_o          (),
        .p2l_low_imp_o (),
        .p2h_low_imp_o (),
        .p1_i          (8'hFF),
        .p1_o          (),
        .p1_low_imp_o  (),
        .prog_n_o      ()
    );

    assign dummy = 1'b0;
endmodule
