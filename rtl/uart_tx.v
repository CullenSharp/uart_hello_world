// uart_tx.v -- Minimal 8N1 UART transmitter (start bit, 8 data bits LSB-first,
// no parity, 1 stop bit) with a plain i_DV/i_Byte handshake.
//
// Timing is expressed in clock cycles per bit (CLKS_PER_BIT) rather than in
// seconds, which keeps the module usable at any clock frequency.

`timescale 1ns / 1ps
`default_nettype none

module uart_tx #(
    // Clock cycles per serial bit. The Go Board top level uses
    // 25_000_000 / 115_200 = 217. Must be >= 2.
    parameter integer CLKS_PER_BIT = 217
) (
    input  wire       i_Clk,
    input  wire       i_Rst,    // synchronous, active high
    input  wire       i_DV,     // asserted to load i_Byte and start a frame
    input  wire [7:0] i_Byte,   // byte to send, LSB transmitted first
    output wire       o_Tx,     // serial output, idles high
    output wire       o_Active, // high while a frame is on the wire
    output wire       o_Done    // one-cycle pulse when the stop bit completes
);

    // Width needed to hold CLKS_PER_BIT-1. Constants that get compared against
    // narrow registers are staged through a 32-bit localparam and then sliced,
    // which keeps every operand width-matched for the linters.
    localparam integer CNT_W         = $clog2(CLKS_PER_BIT);
    localparam [31:0]  CNT_LAST_FULL = CLKS_PER_BIT - 1;
    localparam [CNT_W-1:0] CNT_LAST  = CNT_LAST_FULL[CNT_W-1:0];

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]       r_State  = S_IDLE;
    reg [CNT_W-1:0] r_ClkCnt = {CNT_W{1'b0}};
    reg [2:0]       r_BitIdx = 3'd0;
    reg [7:0]       r_Shift  = 8'h00;
    reg             r_Tx     = 1'b1;
    reg             r_Done   = 1'b0;

    assign o_Tx     = r_Tx;
    assign o_Active = (r_State != S_IDLE);
    assign o_Done   = r_Done;

    always @(posedge i_Clk) begin
        if (i_Rst) begin
            r_State  <= S_IDLE;
            r_ClkCnt <= {CNT_W{1'b0}};
            r_BitIdx <= 3'd0;
            r_Shift  <= 8'h00;
            r_Tx     <= 1'b1;
            r_Done   <= 1'b0;
        end else begin
            r_Done <= 1'b0;

            case (r_State)
                S_IDLE: begin
                    r_Tx <= 1'b1;
                    if (i_DV) begin
                        r_Shift  <= i_Byte;
                        r_BitIdx <= 3'd0;
                        r_ClkCnt <= {CNT_W{1'b0}};
                        r_Tx     <= 1'b0;  // start bit begins this cycle
                        r_State  <= S_START;
                    end
                end

                S_START: begin
                    if (r_ClkCnt == CNT_LAST) begin
                        r_ClkCnt <= {CNT_W{1'b0}};
                        r_Tx     <= r_Shift[0];  // data bit 0
                        r_State  <= S_DATA;
                    end else begin
                        r_ClkCnt <= r_ClkCnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (r_ClkCnt == CNT_LAST) begin
                        r_ClkCnt <= {CNT_W{1'b0}};
                        if (r_BitIdx == 3'd7) begin
                            r_Tx    <= 1'b1;  // stop bit
                            r_State <= S_STOP;
                        end else begin
                            r_BitIdx <= r_BitIdx + 1'b1;
                            r_Shift  <= {1'b0, r_Shift[7:1]};
                            r_Tx     <= r_Shift[1];  // next bit, before the shift
                        end
                    end else begin
                        r_ClkCnt <= r_ClkCnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (r_ClkCnt == CNT_LAST) begin
                        r_ClkCnt <= {CNT_W{1'b0}};
                        r_Tx     <= 1'b1;
                        r_Done   <= 1'b1;
                        r_State  <= S_IDLE;
                    end else begin
                        r_ClkCnt <= r_ClkCnt + 1'b1;
                    end
                end

                default: r_State <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
