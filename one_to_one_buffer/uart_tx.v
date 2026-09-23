module uart_tx #(
    parameter CLKS_PER_BIT = 868 // 100 MHz / 921600 baud = 868
)(  input clk,
    input tx_start,
    input tx_end,
    input [7:0] tx_byte,
    output reg tx_serial,
    output tx_busy
);

    parameter IDLE         = 2'b00;
    parameter TX_START_BIT = 2'b01;
    parameter TX_DATA_BITS = 2'b10;
    parameter TX_STOP_BIT  = 2'b11;

    reg [1:0] state       = IDLE;
    reg [10:0] clk_count  = 0;
    reg [2:0] bit_index   = 0;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                tx_serial <= 1'b1; // Idle state is high
                clk_count <= 0;
                bit_index <= 0;

                if (tx_start || tx_end) begin
                    state <= TX_START_BIT;
                end else begin
                    state <= IDLE;
                end
            end

            TX_START_BIT: begin
                tx_serial <= 1'b0; // Start bit is low
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count <= clk_count + 1;
                    state     <= TX_START_BIT;
                end else begin
                    clk_count <= 0;
                    state     <= TX_DATA_BITS;
                end
            end

            TX_DATA_BITS: begin
                tx_serial <= tx_byte[bit_index];
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count <= clk_count + 1;
                    state     <= TX_DATA_BITS;
                end else begin
                    clk_count <= 0;
                    if (bit_index < 7) begin
                        bit_index <= bit_index + 1;
                        state     <= TX_DATA_BITS;
                    end else begin
                        bit_index <= 0;
                        state     <= TX_STOP_BIT;
                    end
                end
            end

            TX_STOP_BIT: begin
                tx_serial <= 1'b1; // Stop bit is high
                if (clk_count < CLKS_PER_BIT - 1) begin
                    clk_count <= clk_count + 1;
                    state     <= TX_STOP_BIT;
                end else begin
                    clk_count <= 0;
                    state     <= IDLE; // Return to idle after
                end
            end
        endcase 
    end

   assign tx_busy = (state != IDLE);

endmodule