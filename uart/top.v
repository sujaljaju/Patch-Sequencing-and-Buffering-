module top #(
    parameter NUM_WORDS = 10, 
    // Automatically calculates the number of switches needed (e.g., 5 words = 3 switches, 80 words = 7 switches)
    parameter ADDR_WIDTH = $clog2(NUM_WORDS) 
)(
    input clk,                       // 100 MHz clock
    input rx,                        // UART RX pin
    input reset,                     // Reset button (e.g., BTNC)
    input [ADDR_WIDTH-1:0] sw,       // Switches for memory address selection
    output [7:0] anode,              // 7-segment Anodes
    output [6:0] seg                 // 7-segment Cathodes
);

    // Wires for UART
    wire rx_dv;
    wire [7:0] rx_byte;
    
    // Instantiate UART Receiver
    uart_rx #(.CLKS_PER_BIT(10416)) uart_inst (
        .clk(clk),
        .rx_serial(rx),
        .rx_dv(rx_dv),
        .rx_byte(rx_byte)
    );

    // Flexible Memory Buffer
    reg [31:0] mem_buffer [0:NUM_WORDS-1];
    
    // Counters for assembly
    reg [1:0] byte_count = 0;              // Counts 0 to 3 to assemble 4 bytes
    reg [ADDR_WIDTH-1:0] word_count = 0;   // Automatically sized word counter
    reg [31:0] current_word = 0;
    
    integer i; // Used for the reset loop

    // Data Assembly Logic
    always @(posedge clk) begin
        if (reset) begin
            byte_count <= 0;
            word_count <= 0;
            current_word <= 0;
            
            // Loop to clear all memory addresses regardless of size
            for (i = 0; i < NUM_WORDS; i = i + 1) begin
                mem_buffer[i] <= 32'd0;
            end
            
        end else if (rx_dv) begin
            // Shift byte in (Big Endian format)
            current_word <= {current_word[23:0], rx_byte};
            
            if (byte_count == 3) begin
                // We have a full 32-bit word, save it to the buffer
                mem_buffer[word_count] <= {current_word[23:0], rx_byte};
                byte_count <= 0;
                
                // Increment word counter, loop back to 0 if we hit the limit
                if (word_count == NUM_WORDS - 1)
                    word_count <= 0;
                else
                    word_count <= word_count + 1;
            end else begin
                byte_count <= byte_count + 1;
            end
        end
    end

    // Dynamic Mux to select memory address based on Switches
    reg [31:0] display_data;
    always @(*) begin
        // If the switch address is within valid buffer limits, show the data
        if (sw < NUM_WORDS) begin
            display_data = mem_buffer[sw];
        end else begin
            // Show FFFFFFFF if the switch is set to an address outside the buffer size
            display_data = 32'hFFFFFFFF; 
        end
    end

    // Instantiate 7-Segment Display Controller
    seven_seg_drive display_inst (
        .clk(clk),
        .data_in(display_data),
        .anode(anode),
        .seg(seg)
    );

endmodule