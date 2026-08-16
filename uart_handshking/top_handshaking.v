module top #(
    parameter NUM_WORDS = 80, 
    parameter ADDR_WIDTH = $clog2(NUM_WORDS) 
)(
    input clk,                       // 100 MHz clock
    input rx,                        // UART RX pin
    input reset,                     // Reset button (e.g., BTNC)
    input [ADDR_WIDTH-1:0] sw,       // Switches for memory address selection
    output tx,                       // UART TX pin
    output [7:0] anode,              // 7-segment Anodes
    output [6:0] seg                 // 7-segment Cathodes
);

    // Wires for UART
    wire rx_dv;
    wire [7:0] rx_byte;
    reg tx_start;
    reg tx_end;
    reg [7:0] tx_byte;

    
    // Instantiate UART Receiver
    uart_rx #(.CLKS_PER_BIT(108)) uart_inst (
        .clk(clk),
        .rx_serial(rx),
        .rx_dv(rx_dv),
        .rx_byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(108)) uart_tx_inst (
        .clk(clk),
        .tx_start(tx_start), 
        .tx_end(tx_end),   
        .tx_byte(tx_byte), 
        .tx_serial(tx)               
    );

    // Flexible Memory Buffer
    reg [31:0] mem_buffer [0:NUM_WORDS-1];
    
    // Counters for assembly
    reg [1:0] byte_count = 0;              // Counts 0 to 3 to assemble 4 bytes
    reg [ADDR_WIDTH-1:0] word_count = 0;   // Automatically sized word counter
    reg [31:0] current_word = 0;

    localparam IDLE         = 3'd0;
    localparam GET_LENGTH   = 3'd1;
    localparam SEND_READY   = 3'd2;
    localparam RECEIVE_DATA = 3'd3;
    localparam WAIT_END     = 3'd4;
    localparam SEND_ACK     = 3'd5;

    reg [2:0] state = IDLE;
    
    // Handshake tracking registers
    reg [7:0] target_words = 0;
    reg [7:0] received_words = 0;
    
    integer i;
   // --- Master FSM & Data Assembly Logic ---
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            byte_count <= 0;
            word_count <= 0;
            current_word <= 0;
            received_words <= 0;
            
            // Default TX triggers
            tx_start <= 1'b0;
            tx_end <= 1'b0;
            
            for (i = 0; i < NUM_WORDS; i = i + 1) begin
                mem_buffer[i] <= 32'd0;
            end
            
        end else begin
            // Default TX triggers to 0 so they only pulse for exactly one clock cycle
            tx_start <= 1'b0;
            tx_end <= 1'b0;

            case (state)
                IDLE: begin
                    received_words <= 0;
                    byte_count <= 0;
                    
                    // Only transition if rx_dv is high AND the byte is 'S' (0x53)
                    if (rx_dv && rx_byte == 8'h53) begin 
                        state <= GET_LENGTH;
                    end
                end

                GET_LENGTH: begin
                    // Wait for the next valid byte, which is our word count
                    if (rx_dv) begin
                        target_words <= rx_byte;
                        state <= SEND_READY;
                    end
                end

                SEND_READY: begin
                    // Pulse tx_start and load 'R' (0x52)
                    tx_start <= 1'b1;
                    tx_byte  <= 8'h52; 
                    state    <= RECEIVE_DATA;
                end

                RECEIVE_DATA: begin
                    if (rx_dv) begin
                        // Shift byte in
                        current_word <= {current_word[23:0], rx_byte};
                        
                        if (byte_count == 3) begin
                            // Save to memory buffer
                            mem_buffer[word_count] <= {current_word[23:0], rx_byte};
                            byte_count <= 0;
                            
                            // Increment how many words we have successfully received this session
                            received_words <= received_words + 1;
                            
                            // Memory pointer logic
                            if (word_count == NUM_WORDS - 1)
                                word_count <= 0;
                            else
                                word_count <= word_count + 1;
                                
                            // If we have received the exact number of words the CPU promised, stop listening to data
                            if (received_words + 1 == target_words) begin
                                state <= WAIT_END;
                            end
                            
                        end else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                end

                WAIT_END: begin
                    // wait until we see the 'E' (0x45) command
                    if (rx_dv && rx_byte == 8'h45) begin 
                        state <= SEND_ACK;
                    end
                end

                SEND_ACK: begin
                    // Pulse tx_end and load 'A' (0x41)
                    tx_end  <= 1'b1;
                    tx_byte <= 8'h41; 
                    state   <= IDLE; // Session complete, go back to waiting for a new connection
                end
                
                default: state <= IDLE;
            endcase
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