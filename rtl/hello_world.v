// hello_world.v -- Top level: repeatedly prints a greeting over the Go Board UART.
//
// Target: Nandland Go Board, Lattice iCE40HX1K-VQ100, 25 MHz oscillator.

`timescale 1ns / 1ps
`default_nettype none

module hello_world #(
    parameter integer CLK_FREQ_HZ = 25_000_000,  // Go Board oscillator
    parameter integer BAUD        = 115_200,
    parameter integer GAP_MS      = 500          // pause between messages
) (
    input  wire i_Clk,      // 25 MHz, pin 15
    output wire o_UART_TX,  // pin 74
    output wire o_LED_1     // pin 56, toggles once per message sent
);

    // 25_000_000 / 115_200 = 217. Actual line rate 115207.4 baud (+0.006%).
    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;
    localparam integer GAP_CLKS     = (CLK_FREQ_HZ / 1000) * GAP_MS;

    // The greeting is held as one packed vector, leftmost character in the
    // most-significant byte. CRLF is spelled out with explicit bytes because
    // not every Verilog front end recognises the \r escape inside a string.
    localparam integer MSG_LEN = 15;
    localparam [MSG_LEN*8-1:0] MESSAGE = {"Hello, World!", 8'h0D, 8'h0A};
    localparam integer IDX_W   = $clog2(MSG_LEN);
    // Compare constants are staged through 32 bits and sliced down so every
    // operand in a comparison is width-matched.
    localparam [31:0]  IDX_LAST_FULL = MSG_LEN - 1;
    localparam [IDX_W-1:0] IDX_LAST  = IDX_LAST_FULL[IDX_W-1:0];

    // Power-on reset: iCE40 flip-flops are cleared by the global reset that
    // the device asserts throughout configuration, so the declared initializers
    // below seed simulation only. This counter is what actually establishes the
    // power-on state in hardware -- see docs/architecture.md.
    localparam integer POR_CLKS = 16;
    localparam [31:0]  POR_LAST_FULL = POR_CLKS - 1;
    localparam [3:0]   POR_LAST      = POR_LAST_FULL[3:0];
    reg [3:0] r_PorCnt = 4'd0;
    wire w_Rst = (r_PorCnt != POR_LAST);

    always @(posedge i_Clk) begin
        if (w_Rst) r_PorCnt <= r_PorCnt + 1'b1;
    end

    // Sequencer phases.
    localparam integer GAP_CLKS_W = $clog2(GAP_CLKS + 1);
    localparam [31:0]  GAP_LAST_FULL = GAP_CLKS - 1;
    localparam [GAP_CLKS_W-1:0] GAP_LAST = GAP_LAST_FULL[GAP_CLKS_W-1:0];

    localparam [1:0] P_SEND = 2'd0,   // hand a byte to the transmitter
                     P_WAIT = 2'd1,   // wait for that byte to finish
                     P_GAP  = 2'd2;   // idle between messages

    reg [1:0]            r_Phase  = P_SEND;
    reg [IDX_W-1:0]      r_Index  = {IDX_W{1'b0}};
    reg [GAP_CLKS_W-1:0] r_GapCnt = {GAP_CLKS_W{1'b0}};
    reg                  r_Dv     = 1'b0;
    reg                  r_Led    = 1'b0;

    // Character selector: index 0 reads the most-significant byte. The index
    // is widened explicitly so the address arithmetic stays 32 bits.
    wire [31:0] w_MsgIdx = {28'd0, r_Index};
    wire [7:0]  w_Byte   = MESSAGE[(MSG_LEN - 1 - w_MsgIdx)*8 +: 8];

    wire w_TxActive;
    wire w_TxDone;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart_tx_i (
        .i_Clk     (i_Clk),
        .i_Rst     (w_Rst),
        .i_DV      (r_Dv),
        .i_Byte    (w_Byte),
        .o_Tx      (o_UART_TX),
        .o_Active  (w_TxActive),
        .o_Done    (w_TxDone)
    );

    always @(posedge i_Clk) begin
        if (w_Rst) begin
            r_Phase  <= P_SEND;
            r_Index  <= {IDX_W{1'b0}};
            r_GapCnt <= {GAP_CLKS_W{1'b0}};
            r_Dv     <= 1'b0;
            r_Led    <= 1'b0;
        end else begin
            case (r_Phase)
                P_SEND: begin
                    r_Dv <= 1'b1;
                    if (w_TxActive) begin
                        r_Dv    <= 1'b0;
                        r_Phase <= P_WAIT;
                    end
                end

                P_WAIT: begin
                    r_Dv <= 1'b0;
                    if (w_TxDone) begin
                        if (r_Index == IDX_LAST) begin
                            r_Index  <= {IDX_W{1'b0}};
                            r_GapCnt <= {GAP_CLKS_W{1'b0}};
                            r_Led    <= ~r_Led;  // heartbeat, one toggle per message
                            r_Phase  <= P_GAP;
                        end else begin
                            r_Index <= r_Index + 1'b1;
                            r_Phase <= P_SEND;
                        end
                    end
                end

                P_GAP: begin
                    if (r_GapCnt == GAP_LAST) begin
                        r_GapCnt <= {GAP_CLKS_W{1'b0}};
                        r_Phase  <= P_SEND;
                    end else begin
                        r_GapCnt <= r_GapCnt + 1'b1;
                    end
                end

                default: r_Phase <= P_SEND;
            endcase
        end
    end

    assign o_LED_1 = r_Led;

endmodule

`default_nettype wire
