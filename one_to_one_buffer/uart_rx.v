module uart_rx #(
    parameter CLKS_PER_BIT = 108 // 100 MHz / 115200 baud = 868
)(
    input        clk,
    input        rx_serial,
    output reg       rx_dv,
    output reg [7:0] rx_byte
);

    parameter IDLE         = 2'b00;
    parameter RX_START_BIT = 2'b01;
    parameter RX_DATA_BITS = 2'b10;
    parameter RX_STOP_BIT  = 2'b11;
   // parameter CLEANUP      = 3'b100;
    
    reg [1:0]  state       = IDLE;
    reg [10:0] clk_count   = 0;
    reg [2:0]  bit_index   = 0; 

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                rx_dv       <= 1'b0;
                clk_count   <= 0;
                bit_index   <= 0;
                
                if (rx_serial == 1'b0) // Start bit detected
                    state <= RX_START_BIT;
                else
                    state <= IDLE;
            end
            
             RX_START_BIT: begin
                if (clk_count == (CLKS_PER_BIT)/2) begin
                    if (rx_serial == 1'b0) begin
                        clk_count <= 0;
                        state     <= RX_DATA_BITS;
                    end 
                    else
                    state <= IDLE;
                end else begin
                    clk_count <= clk_count + 1;
                    state     <= RX_START_BIT;
                end
            end               
            
            RX_DATA_BITS: begin
                if (clk_count < CLKS_PER_BIT-1) begin
                    clk_count <= clk_count + 1;
                    state     <= RX_DATA_BITS;
                end else begin
                    clk_count          <= 0;
                    rx_byte[bit_index] <= rx_serial;
                    
                    if (bit_index < 7) begin
                        bit_index <= bit_index + 1;
                        state     <= RX_DATA_BITS;
                    end else begin
                        bit_index <= 0;
                        state     <= RX_STOP_BIT;
                    end
                end
            end
            
            RX_STOP_BIT: begin
                if (clk_count < CLKS_PER_BIT-1) begin
                    clk_count <= clk_count + 1;
                    state     <= RX_STOP_BIT;
                end else begin
                    rx_dv     <= 1'b1;
                    clk_count <= 0;
                    state     <= IDLE;
                end
            end
            
        //    CLEANUP: begin
        //        state <= IDLE;
        //       rx_dv <= 1'b0;
        //   end
            
            default: state <= IDLE;
        endcase
    end
endmodule
