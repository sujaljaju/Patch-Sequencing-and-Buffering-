module psa #(
    parameter NUM_WORDS = 80, 
    parameter ADDR_WIDTH = $clog2(NUM_WORDS) 
)(
    input clk,                       
    input rx,                        
    input reset,                     
    input send_btn,   
    input push,               
    input [ADDR_WIDTH-1:0] sw,       
    output tx,                       
    output [7:0] anode,              
    output [6:0] seg,
    output [15:1] led,
    output [ADDR_WIDTH-1:0] word_count ,
    output [31:0] data_out,
    output ready             
      
);

    // Wires for UART
    wire rx_dv;
    wire [7:0] rx_byte;
    reg tx_start;
    reg tx_end;
    reg [7:0] tx_byte;
    wire tx_busy;

    // Edge detector for btn_send
    reg send_btn_prev = 0;
    wire send_btn_edge = (send_btn && !send_btn_prev);

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
        .tx_busy(tx_busy)               
    );

    reg [31:0] mem_buffer [0:NUM_WORDS-1];
    reg [1:0] byte_count = 0;              
    reg [ADDR_WIDTH-1:0] word_count = 0;   
    reg [31:0] current_word = 0;

    // FSM States
    localparam IDLE                = 4'd0;
    localparam GET_LENGTH          = 4'd1;
    localparam SEND_READY          = 4'd2;
    localparam RECEIVE_DATA        = 4'd3;
    localparam SEND_NEW_DATA_ACK   = 4'd4;
    localparam SEND_ACK            = 4'd5;
    localparam BUFFER_EMPTY        = 4'd6;
    localparam WAIT_TX_READY       = 4'd7;
    localparam STREAM_WORDCOUNT    = 4'd13;
    localparam STREAM_DATA         = 4'd8;
    localparam STREAM_DONE         = 4'd9;
    localparam WAIT_TX_END         = 4'd10;
    localparam WAIT_TX_READY_DELAY = 4'd11;
    localparam WAIT_TX_END_DELAY   = 4'd12; 
    
    reg [3:0] state = IDLE;
    integer i;

    // --- LED STATE MAPPING ---
    // The LED matching the current state will glow brightly
    assign led[0]  = (state == IDLE);
    assign led[1]  = (state == GET_LENGTH);
    assign led[2]  = (state == SEND_READY);
    assign led[3]  = (state == RECEIVE_DATA);
    assign led[4]  = (state == SEND_NEW_DATA_ACK);
    assign led[5]  = (state == SEND_ACK);
    assign led[6]  = (state == BUFFER_EMPTY); // Should sit here while waiting for button
    assign led[7]  = (state == WAIT_TX_READY);
    assign led[8]  = (state == STREAM_WORDCOUNT);
    assign led[9]  = (state == STREAM_DATA);
    assign led[10]  = (state == STREAM_DONE);
    assign led[11] = (state == WAIT_TX_END);
    assign led[12] = (state == WAIT_TX_READY_DELAY);
    assign led[13] = (state == WAIT_TX_END_DELAY);
    assign led[15:14] = 2'b00; // Unused LEDs kept off

    reg [7:0] target_words = 0;
    reg [ADDR_WIDTH-1:0] received_words = 0;
    reg [ADDR_WIDTH-1:0] read_ptr = 0;

    assign data_out = mem_buffer[read_ptr];
    
    always @(posedge clk) begin
        send_btn_prev <= send_btn; 
    
        if (reset) begin
            state <= IDLE;
            byte_count <= 0;
            word_count <= 0;
            current_word <= 0;
            received_words <= 0;
            read_ptr <= 0;
            tx_byte <= 8'd0;
            tx_start <= 1'b0;
            tx_end <= 1'b0;
            push <= 1'b0; 
            
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

                    if (rx_dv && rx_byte == 8'h53) begin 
                        state <= SEND_READY;
                    end else begin
                        state <= IDLE; 
                    end
                end

                SEND_READY: begin
                    tx_start <= 1'b1;
                    tx_byte  <= 8'h52; 
                    state    <= WAIT_TX_READY_DELAY; 
                end

                WAIT_TX_READY_DELAY: begin
                    state <= WAIT_TX_READY; 
                end

                WAIT_TX_READY: begin
                    if (!tx_busy) begin 
                        state <= BUFFER_EMPTY;
                    end
                end

                BUFFER_EMPTY: begin
                    if (received_words == 0) begin
                        state <= SEND_NEW_DATA_ACK;
                    end
                    else if (send_btn_edge && push) begin
                        state <= STREAM_WORDCOUNT;
                    end
                end

                SEND_NEW_DATA_ACK: begin
                    tx_start <= 1'b1;
                    tx_byte  <= 8'h50; 
                    state    <= GET_LENGTH;
                end

                GET_LENGTH: begin
                    if (rx_dv) begin
                        target_words <= rx_byte;
                        received_words <= 0; 
                        byte_count <= 0;
                        word_count <= 0;
                        state <= RECEIVE_DATA;
                    end
                    else if (send_btn_edge && push) begin
                        state <= STREAM_DATA;
                    end
                end

                RECEIVE_DATA: begin
                    if (rx_dv) begin
                        current_word <= {current_word[23:0], rx_byte};
                        
                        if (byte_count == 3) begin
                            mem_buffer[word_count] <= {current_word[23:0], rx_byte};
                            byte_count <= 0;
                            received_words <= received_words + 1;
                            
                            if (word_count == NUM_WORDS - 1) word_count <= 0;
                            else word_count <= word_count + 1;
                                
                            if (received_words + 1 == target_words) begin
                                state <= SEND_ACK;
                            end
                        end else begin
                            byte_count <= byte_count + 1;
                        end
                    end
                end

                SEND_ACK: begin
                    tx_start <= 1'b1; 
                    tx_byte  <= 8'h51; 
                    push     <= 1'b1; 
                    state    <= WAIT_TX_END_DELAY; 
                end

                WAIT_TX_END_DELAY: begin
                    state <= WAIT_TX_END; 
                end

                WAIT_TX_END: begin
                    if (!tx_busy) begin
                        state <= BUFFER_EMPTY; 
                    end
                end

                STREAM_WORDCOUNT: begin
                    if (ready && push) begin
                        word_count <= received_words;     
                        state    <= STREAM_DATA; 
                        end
                    end 
                end

                STREAM_DATA: begin
                    if (read_ptr + 1 == received_words) begin
                        read_ptr <= 0; 
                        state <= STREAM_DONE;
                    end else begin
                        read_ptr <= read_ptr + 1;
                    end      
                    
                end

                STREAM_DONE: begin
                    state <= BUFFER_EMPTY;
                    push <= 1'b0; 
                    received_words <= 0; 
                    read_ptr <= 0;

                    for (i = 0; i < NUM_WORDS; i = i + 1) begin
                        mem_buffer[i] <= 32'd0;
                    end 
                end
   
                default: state <= IDLE;
            endcase
        end
    end

    reg [31:0] display_data;
    always @(*) begin
        if (sw < NUM_WORDS) begin
            display_data = mem_buffer[sw];
        end else begin
            display_data = 32'hFFFFFFFF; 
        end
    end

    seven_seg_drive display_inst (
        .clk(clk),
        .data_in(display_data),
        .anode(anode),
        .seg(seg)
    );

endmodule