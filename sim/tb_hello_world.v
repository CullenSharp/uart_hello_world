// tb_hello_world.v -- Self-checking testbench for the hello_world top level.
//
// Models a real terminal: it waits for the falling edge of each start bit and
// samples the line at the centre of every bit. Each received character is
// printed to stdout and compared against the expected greeting, so a passing
// run literally shows "Hello, World!" in the console.

`timescale 1ns / 1ps
`default_nettype none

module tb_hello_world;

    localparam integer CLK_PERIOD_NS = 40;          // 25 MHz
    localparam real    BIT_TIME_NS   = 1.0e9 / 115200.0;
    localparam integer MSG_LEN       = 15;

    // Same text the RTL transmits; must be kept in sync with rtl/hello_world.v.
    // Explicit bytes for CRLF -- see the note in the RTL.
    localparam [MSG_LEN*8-1:0] EXPECTED = {"Hello, World!", 8'h0D, 8'h0A};

    reg i_Clk = 1'b0;
    wire o_UART_TX;
    wire o_LED_1;

    always #(CLK_PERIOD_NS / 2) i_Clk = ~i_Clk;

    // A 2 ms repeat gap keeps the run short; everything that matters
    // (baud, framing, message, LED) matches the synthesised configuration.
    hello_world #(.GAP_MS(2)) dut (
        .i_Clk     (i_Clk),
        .o_UART_TX (o_UART_TX),
        .o_LED_1   (o_LED_1)
    );

    integer errors     = 0;
    integer char_count = 0;
    integer led_toggles = 0;
    reg [7:0] rx_byte;
    reg [7:0] exp_byte;
    integer b;

    // Counts LED transitions after time 0 (the DUT settles its initial value
    // at time 0, which is not a real toggle).
    always @(o_LED_1) if ($time > 0) led_toggles = led_toggles + 1;

    // ---- UART receiver model ----
    initial begin : uart_monitor
        forever begin
            @(negedge o_UART_TX);        // start bit begins
            #(BIT_TIME_NS * 1.5);        // centre of data bit 0
            for (b = 0; b < 8; b = b + 1) begin
                rx_byte[b] = o_UART_TX;
                #(BIT_TIME_NS);
            end
            // Now at the centre of the stop bit.
            if (o_UART_TX !== 1'b1) begin
                $display("");
                $display("ERROR: framing error on char %0d (stop bit not high)",
                         char_count);
                errors = errors + 1;
            end

            // char_count runs over both messages, so fold it back onto the
            // expected string for the second pass.
            exp_byte = EXPECTED[(MSG_LEN - 1 - (char_count % MSG_LEN)) * 8 +: 8];
            if (rx_byte !== exp_byte) begin
                $display("");
                $display("ERROR: char %0d expected 0x%02h ('%c'), got 0x%02h ('%c')",
                         char_count, exp_byte, exp_byte, rx_byte, rx_byte);
                errors = errors + 1;
            end

            $write("%c", rx_byte);
            $fflush(32'h8000_0001);
            char_count = char_count + 1;
        end
    end

    // ---- End of test ----
    initial begin : watchdog
        #(10_000_000);  // 10 ms: two messages at 2 ms spacing should need ~5 ms
        $display("");
        $display("FAIL: timeout after %0d characters (expected %0d)",
                 char_count, MSG_LEN * 2);
        $fatal(1);
    end

    initial begin : main
        wait (char_count >= MSG_LEN * 2);
        #(BIT_TIME_NS * 4);  // let the final stop bit and LED toggle land

        $display("");

        if (char_count != MSG_LEN * 2) begin
            $display("FAIL: received %0d characters, expected %0d",
                     char_count, MSG_LEN * 2);
            errors = errors + 1;
        end
        if (led_toggles != 2) begin
            $display("FAIL: LED toggled %0d times over 2 messages, expected 2",
                     led_toggles);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: %0d characters received over UART, LED heartbeat OK",
                     char_count);
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $fatal(1);
        end
    end

    `ifdef WAVES
    initial begin
        $dumpfile("build/hello_world.vcd");
        $dumpvars(0, tb_hello_world);
    end
    `endif

endmodule

`default_nettype wire
