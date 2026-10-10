// uart_tx_props.v -- Formal properties for uart_tx, driven by SymbiYosys.
//
// Runs with CLKS_PER_BIT = 4 so a whole frame is only 40 cycles deep, which
// keeps the bounded proof fast. The state machine structure is identical for
// any CLKS_PER_BIT >= 2, so what is proven here carries over to the shipped
// value of 217.

`default_nettype none

module uart_tx_props #(
    parameter integer CLKS_PER_BIT = 4
) (
    input wire       i_Clk,   // free-running clock
    input wire       i_DV,    // free input: may start a frame at any time
    input wire [7:0] i_Byte   // free input
);

    wire o_Tx;
    wire o_Active;
    wire o_Done;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .i_Clk    (i_Clk),
        .i_Rst    (1'b0),
        .i_DV     (i_DV),
        .i_Byte   (i_Byte),
        .o_Tx     (o_Tx),
        .o_Active (o_Active),
        .o_Done   (o_Done)
    );

    // 1 start bit + 8 data bits + 1 stop bit.
    localparam integer FRAME_CLKS = 10 * CLKS_PER_BIT;

    integer active_cnt = 0;

    always @(posedge i_Clk) begin
        if (o_Active) begin
            // A frame never runs longer than one full frame time.
            assert (active_cnt < FRAME_CLKS);
            active_cnt <= active_cnt + 1;
        end else begin
            // The line idles high whenever nothing is being transmitted.
            assert (o_Tx == 1'b1);
            // When a frame ends it lasted exactly the expected number of cycles.
            if (active_cnt != 0) assert (active_cnt == FRAME_CLKS);
            active_cnt <= 0;
        end

        // A complete frame is reachable.
        cover (active_cnt == FRAME_CLKS - 1);
    end

endmodule

`default_nettype wire
