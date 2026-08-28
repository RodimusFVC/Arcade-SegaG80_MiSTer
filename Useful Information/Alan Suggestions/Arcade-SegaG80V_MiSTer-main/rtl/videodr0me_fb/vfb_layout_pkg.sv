package vfb_layout_pkg;

	localparam integer VFB_BUFFER_COUNT = 5;
	localparam integer VFB_TILE_SIZE = 8;
	localparam integer VFB_TILEMAP_STRIDE = 192;
	localparam logic [15:0] VFB_TILEMAP_ENTRIES_480 = 16'd11520;

	function automatic logic [28:0] vfb_buffer_base(
		input logic [2:0] index
	);
		begin
			case (index)
				3'd0: vfb_buffer_base = 29'h06000000;
				3'd1: vfb_buffer_base = 29'h06110000;
				3'd2: vfb_buffer_base = 29'h06220000;
				3'd3: vfb_buffer_base = 29'h06330000;
				3'd4: vfb_buffer_base = 29'h06440000;
				default: vfb_buffer_base = 29'h06000000;
			endcase
		end
	endfunction

	function automatic logic [8:0] vfb_tile_columns(
		input logic [11:0] width
	);
		vfb_tile_columns = 9'((width + 12'd7) >> 3);
	endfunction

	function automatic logic [8:0] vfb_tile_rows(
		input logic [11:0] height
	);
		vfb_tile_rows = 9'((height + 12'd7) >> 3);
	endfunction

	function automatic logic [14:0] vfb_tile_row_addr(
		input logic [7:0] tile_y
	);
		logic [15:0] row_base;
		begin
			row_base = ({8'd0, tile_y} << 7)
			         + ({8'd0, tile_y} << 6);
			vfb_tile_row_addr = row_base[14:0];
		end
	endfunction

	function automatic logic [14:0] vfb_linear_tile_addr(
		input logic [15:0] tile_id
	);
		vfb_linear_tile_addr =
			vfb_tile_row_addr(tile_id[15:8]) + {7'd0, tile_id[7:0]};
	endfunction

	function automatic logic [15:0] vfb_tilemap_entries(
		input logic [8:0] rows
	);
		vfb_tilemap_entries =
			({7'd0, rows} << 7) + ({7'd0, rows} << 6);
	endfunction

endpackage
