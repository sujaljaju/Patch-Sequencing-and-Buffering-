module psa #(
    parameter integer data_width = 32,
    parameter NUM_WORDS = 80, 
    parameter ADDR_WIDTH = $clog2(NUM_WORDS) 
)(
    input clk,                       
    input rx,                        
    input reset,                     
 //   input send_btn,                  
    input [ADDR_WIDTH-1:0] sw,  
    input ready,    //ready signal from sipo   
    output tx,                       
    output [15:0] led,
    output reg [(NUM_WORDS*data_width)-1:0] data_out,
    output reg push   //to sipo           
);

    // Wires for UART
    wire rx_dv;
    wire [7:0] rx_byte;
    reg tx_start;
    reg tx_end;
    reg [7:0] tx_byte;
    wire tx_busy;

    // Edge detector for btn_send
    //reg send_btn_prev = 0;
    //wire send_btn_edge = (send_btn && !send_btn_prev);

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
    reg [ADDR_WIDTH-1:0] word_count_reg = 0;   
    reg [31:0] current_word = 0;

    // FSM States
    localparam IDLE                = 5'd0;
    localparam GET_LENGTH          = 5'd1;
    localparam SEND_READY          = 5'd2;
    localparam RECEIVE_DATA        = 5'd3;
    localparam SEND_NEW_DATA_ACK   = 5'd4;
    localparam SEND_ACK            = 5'd5;
    localparam BUFFER_STATUS       = 5'd6;
    localparam WAIT_TX_READY       = 5'd7;
    localparam STREAM_DATA         = 5'd8;
    localparam STREAM_DONE         = 5'd9;
    localparam WAIT_TX_END         = 5'd10;
    localparam WAIT_TX_READY_DELAY = 5'd11;
    localparam WAIT_TX_END_DELAY   = 5'd12;
    localparam STREAM_WORDCOUNT    = 5'd13; 
    
    reg [4:0] state = IDLE;
    integer i;
    integer j;

    // --- LED STATE MAPPING ---
    // The LED matching the current state will glow brightly
    assign led[0]  = (state == IDLE);
    assign led[1]  = (state == GET_LENGTH);
    assign led[2]  = (state == SEND_READY);
    assign led[3]  = (state == RECEIVE_DATA);
    assign led[4]  = (state == SEND_NEW_DATA_ACK);
    assign led[5]  = (state == SEND_ACK);
    assign led[6]  = (state == BUFFER_STATUS); // Should sit here while waiting for button
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
    //reg [ADDR_WIDTH-1:0] read_ptr = 0;

    reg [1:0] ready_stable_cnt = 0;
    wire ready_confirmed = (ready_stable_cnt == 1'd1);
    always @(posedge clk) begin
        if (reset) begin
            ready_stable_cnt <= 0;
        end else if (ready) begin
            if (ready_stable_cnt < 1'd1) ready_stable_cnt <= ready_stable_cnt + 1'b1;
        end else begin
            ready_stable_cnt <= 0;
        end
    end
       
    always @(posedge clk) begin
       // send_btn_prev <= send_btn; 
    
        if (reset) begin
            state <= IDLE;
            byte_count <= 0;
            word_count_reg <= 0;
            current_word <= 0;
            received_words <= 0;
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
                    word_count_reg <= 0;
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
                        state <= BUFFER_STATUS;
                    end
                end

                BUFFER_STATUS: begin
                    if (received_words == 0) begin
                        state <= SEND_NEW_DATA_ACK;
                    end
                    else if (ready_confirmed && (received_words != 0)) begin
                        state <= STREAM_WORDCOUNT;
                    end
                    else begin
                        state <= BUFFER_STATUS; 
                        
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
                        word_count_reg <= 0; // Resets the write pointer for the new batch
                        state <= RECEIVE_DATA;
                    end
                end

                RECEIVE_DATA: begin
                    if (rx_dv) begin
                        current_word <= {current_word[23:0], rx_byte};
                        
                        if (byte_count == 3) begin
                            mem_buffer[word_count_reg] <= {current_word[23:0], rx_byte};
                            byte_count <= 0;
                            received_words <= received_words + 1;

                            if (word_count_reg == NUM_WORDS - 1) word_count_reg <= 0;
                            else word_count_reg <= word_count_reg + 1;
                                
                            if (received_words == target_words - 1) begin
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
                    state    <= WAIT_TX_END_DELAY; 
                end

                WAIT_TX_END_DELAY: begin
                    state <= WAIT_TX_END; 
                end

                WAIT_TX_END: begin
                    if (!tx_busy) begin
                        state <= BUFFER_STATUS; 
                    end
                end

                STREAM_WORDCOUNT: begin
                    if (ready_confirmed) begin
                        push     <= 1'b1;     
                        state <= 5'd14;            
                    end 
                end

                // Wait for SIPO's push_stable_cnt to reach 2
                5'd14: begin
                    state <= 5'd15;
                end
                
                5'd15: begin
                    state <= 5'd16; // Added an extra wait state
                end

                // Now SIPO is safely inside GET_DATA
                5'd16: begin
                    state <= STREAM_DATA;
                end


                STREAM_DATA: begin
                    for (j = 0; j < NUM_WORDS; j = j + 1) begin
                            data_out[j*data_width +: data_width] <= mem_buffer[j];
                        end
                        state <= STREAM_DONE; 
                    end 

                STREAM_DONE: begin
                    state <= BUFFER_STATUS;
                    push <= 1'b0;
                    received_words <= 0;

                    for (i = 0; i < NUM_WORDS; i = i + 1) begin
                        mem_buffer[i] <= 32'd0;
                    end 
                end
   
                default: state <= IDLE;
            endcase
        end
    end

endmodule
