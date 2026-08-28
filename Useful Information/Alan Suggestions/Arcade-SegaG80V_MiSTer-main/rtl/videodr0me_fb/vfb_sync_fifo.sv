// ============================================================================
// FIFO for SDRAM staging.
// written 2026 by Videodr0me
// ============================================================================

module vfb_sync_fifo #(
	parameter integer WIDTH = 32,
	parameter integer DEPTH = 256,
	parameter integer ADDR_W = $clog2(DEPTH)
) (
	input  logic              clk_sys,
	input  logic              reset,

	input  logic              wr_en,
	input  logic [WIDTH-1:0]  wr_data,
	output logic              full,

	input  logic              rd_en,
	output logic [WIDTH-1:0]  rd_data,
	output logic              empty,

	output logic [ADDR_W:0]   used
);

	localparam logic [ADDR_W:0] DEPTH_COUNT = {1'b1, {ADDR_W{1'b0}}};

	initial begin
		if ((DEPTH & (DEPTH - 1)) != 0)
			$error("vfb_sync_fifo DEPTH must be a power of two");
	end

	(* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] memory [0:DEPTH-1];
	logic [ADDR_W-1:0] write_ptr;
	logic [ADDR_W-1:0] read_ptr;
	logic [ADDR_W:0] mem_used;
	logic head_valid;
	logic look_valid;
	logic [WIDTH-1:0] look_data;
	logic prefetch_pending;
	logic [ADDR_W-1:0] prefetch_addr;

	assign full = (used == DEPTH_COUNT);
	assign empty = !head_valid;

	wire push = wr_en && !full;
	wire pop  = rd_en && head_valid;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			write_ptr        <= '0;
			read_ptr         <= '0;
			mem_used         <= '0;
			head_valid       <= 1'b0;
			look_valid       <= 1'b0;
			prefetch_pending <= 1'b0;
			prefetch_addr    <= '0;
			rd_data          <= '0;
			look_data        <= '0;
			used             <= '0;
		end else begin
			logic [ADDR_W-1:0] write_ptr_next;
			logic [ADDR_W-1:0] read_ptr_next;
			logic [ADDR_W:0] mem_used_next;
			logic head_valid_next;
			logic look_valid_next;
			logic [WIDTH-1:0] rd_data_next;
			logic [WIDTH-1:0] look_data_next;
			logic prefetch_pending_next;
			logic [ADDR_W-1:0] prefetch_addr_next;
			logic [ADDR_W:0] used_next;

			write_ptr_next        = write_ptr;
			read_ptr_next         = read_ptr;
			mem_used_next         = mem_used;
			head_valid_next       = head_valid;
			look_valid_next       = look_valid;
			rd_data_next          = rd_data;
			look_data_next        = look_data;
			prefetch_pending_next = prefetch_pending;
			prefetch_addr_next    = prefetch_addr;
			used_next             = used;

			case ({push, pop})
				2'b10: used_next = used + 1'b1;
				2'b01: used_next = used - 1'b1;
				default: used_next = used;
			endcase

			if (!head_valid_next && look_valid_next) begin
				rd_data_next = look_data_next;
				head_valid_next = 1'b1;
				look_valid_next = 1'b0;
			end

			if (pop) begin
				if (look_valid_next) begin
					rd_data_next = look_data_next;
					look_valid_next = 1'b0;
				end else begin
					head_valid_next = 1'b0;
				end
			end

			if (push) begin
				if (!head_valid_next && !look_valid_next &&
				    !prefetch_pending_next && mem_used_next == '0) begin
					rd_data_next = wr_data;
					head_valid_next = 1'b1;
				end else if (head_valid_next && !look_valid_next &&
				             !prefetch_pending_next &&
				             mem_used_next == '0) begin
					look_data_next = wr_data;
					look_valid_next = 1'b1;
				end else begin
					memory[write_ptr_next] <= wr_data;
					write_ptr_next = write_ptr_next + 1'b1;
					mem_used_next = mem_used_next + 1'b1;
				end
			end

			if (prefetch_pending_next) begin
				if (!head_valid_next) begin
					rd_data_next = memory[prefetch_addr_next];
					head_valid_next = 1'b1;
				end else begin
					look_data_next = memory[prefetch_addr_next];
					look_valid_next = 1'b1;
				end
				prefetch_pending_next = 1'b0;
			end

			if ((!head_valid_next || !look_valid_next) &&
			    !prefetch_pending_next && mem_used_next != '0) begin
				prefetch_addr_next = read_ptr_next;
				read_ptr_next = read_ptr_next + 1'b1;
				mem_used_next = mem_used_next - 1'b1;
				prefetch_pending_next = 1'b1;
			end

			write_ptr        <= write_ptr_next;
			read_ptr         <= read_ptr_next;
			mem_used         <= mem_used_next;
			head_valid       <= head_valid_next;
			look_valid       <= look_valid_next;
			rd_data          <= rd_data_next;
			look_data        <= look_data_next;
			prefetch_pending <= prefetch_pending_next;
			prefetch_addr    <= prefetch_addr_next;
			used             <= used_next;
		end
	end

endmodule
