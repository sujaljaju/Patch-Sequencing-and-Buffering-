module top #(
    parameter NUM_WORDS = 80, 
    parameter ADDR_WIDTH = $clog2(NUM_WORDS) 
)(
    input clk,                       // 100 MHz clock
    input rx,                        // UART RX pin
    input reset,                     // Reset button (e.g., BTNC)
    input send_btn,                  // Push button for manuual data push between psa and sipo
    input ready,                     // Ready signal from SIPO
    input [ADDR_WIDTH-1:0] sw,       // Switches for memory address selection
    output tx,                       // UART TX pin
    output reg pnc,                  // LED to indicate handshake not complete
    output [7:0] anode,              // 7-segment Anodes
    output [6:0] seg.                // 7-segment Cathodes
    output reg [31:0] data_out = 0,
    output push = 0
);

    // Wires for UART
    wire rx_dv;
    wire [7:0] rx_byte;
    reg tx_start;
    reg tx_end;
    reg [7:0] tx_byte;
    reg tx_busy;

    
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
        .tx_serial(tx),
        .busy(tx_busy)               
    );

    // Memory Buffer
    reg [31:0] mem_buffer [0:NUM_WORDS-1];
    
    // Counters for assembly
    reg [1:0] byte_count = 0;              // Counts 0 to 3 to assemble 4 bytes
    reg [ADDR_WIDTH-1:0] word_count = 0;   // Automatically sized word counter
    reg [31:0] current_word = 0;

    localparam IDLE         = 4'd0;
    localparam GET_LENGTH   = 4'd1;
    localparam SEND_READY   = 4'd2;
    localparam RECEIVE_DATA = 4'd3;
    localparam SEND_NEW_DATA_ACK = 4'd4;
    localparam SEND_ACK     = 4'd5;
    localparam BUFFER_EMPTY  = 4'd6;
    localparam WAIT_TX_READY = 4'd7;
    localparam STREAM_DATA   = 4'd8;
    localparam STREAM_DONE   = 4'd9;
    

    reg [3:0] state = IDLE;
    integer i;

    // Handshake tracking registers
    reg [7:0] target_words = 0;
    reg [7:0] received_words = 0;
    reg [ADDR_WIDTH-1:0] read_ptr = 0;
    reg [ADDR_WIDTH-1:0] valid_word_count = 0;
    
  
   // --- Master FSM & Data Assembly Logic ---
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            byte_count <= 0;
            word_count <= 0;
            current_word <= 0;
            received_words <= 0;
            pnc <= 1'b1; // Indicate handshake not complete


            tx_byte <= 8'd0;
            tx_start <= 1'b0;
            tx_end <= 1'b0;
            
            for (i = 0; i < NUM_WORDS; i = i + 1) begin
                mem_buffer[i] <= 32'd0;
            end
            
        end else begin

            tx_start <= 1'b0;
            tx_end <= 1'b0;

            case (state)
                IDLE: begin
                    received_words <= 0;
                    byte_count <= 0;
                    word_count <= 0;
                    current_word <= 0;

                    // Only transition if rx_dv is high AND the byte is 'S' (0x53)
                    if (rx_dv && rx_byte == 8'h53) begin 
                        state <= SEND_READY;
                        pnc <= 1'b0; // Indicate handshake complete
                    end
                    else begin
                        state <= IDLE; 
                        pnc <= 1'b1; // Indicate handshake not complete
                    end
                    
                end

                SEND_READY: begin
                    // Pulse tx_start and load 'R' (0x52)
                    tx_start <= 1'b1;
                    tx_byte  <= 8'h52; 
                    state    <= WAIT_TX_READY;
                end

                WAIT_TX_READY: begin
                    // Wait for uart_tx to finish sending 'R'
                    if (!tx_busy) begin 
                        state <= BUFFER_EMPTY;
                    end
                end

                BUFFER_EMPTY: begin
                    if (valid_word_count == 0)//buffer is empty, we can send the NEW DATA ACK 
                    begin
                        state <= SEND_NEW_DATA_ACK;
                    end
                    else begin
                        state <= BUFFER_EMPTY;
                    end
                end

                SEND_NEW_DATA_ACK: begin
                    tx_start <= 1'b1;
                    tx_byte  <= 8'h50; 
                    state    <= GET_LENGTH;
                end

                GET_LENGTH: begin
                    // Wait for the next valid byte, which is our word count
                    if (rx_dv) begin
                        target_words <= rx_byte;
                        received_words <= 0; 
                        byte_count <= 0;
                        state <= RECEIVE_DATA;
                    end
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
                                state <= SEND_ACK;
                            end
                            
                        end else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                end

                SEND_ACK: begin
                    tx_end  <= 1'b1;
                    tx_byte <= 8'h51; 
                    state   <= WAIT_TX_END; // Session complete, go back to waiting for a new connection
                end

                WAIT_TX_END: begin
                    if (!tx_busy) begin
                        state <= BUFFER_EMPTY; 
                    end
                end

                SREAM_DATA: begin
                    if (ready) begin
                        data_out <= mem_buffer[read_ptr];
                        push <= 1'b0; 
                        if (read_ptr == valid_word_count) begin
                            read_ptr <= 0; // Reset pointer after last word
                            state <= STREAM_DONE;
                        end else begin
                            read_ptr <= read_ptr + 1;
                        end      
                    end
                end

                STREAM_DONE: begin
                    push <= 1'b1;
                    state <= BUFFER_EMPTY;
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