module master_fsm #(
    parameter integer ADDR_WIDTH    = 7,   
    parameter integer COUNTER_WIDTH = 32,
    parameter integer MIN_WAIT    = 3    // minimum cycles a state must hold before transitioning
)(
    input clk,
    input rst,
    input rts_raw,
    output reg cts,
    input  [ADDR_WIDTH-1:0] word_count_live,
    input stream_done,
    input eoc,                           
    output reg [ADDR_WIDTH-1:0] total_words,  
    output reg stream_enable, 
    output reg batch_clear,                                   
);
    reg rts_sync1, rts_sync2, rts_sync_d;
    always @(posedge clk) begin
        if (rst) begin
            rts_sync1 <= 1'b0;
            rts_sync2 <= 1'b0;
            rts_sync_d <= 1'b0;
        end else begin
            rts_sync1 <= rts_raw;
            rts_sync2 <= rts_sync1;
            rts_sync_d <= rts_sync2;
        end
    end
    wire rts_rising = rts_sync2 & ~rts_sync_d;

    localparam IDLE      = 3'd0;
    localparam RECEIVING = 3'd1;
    localparam STREAM    = 3'd2;
    localparam WAIT_CAP  = 3'd3;
    localparam DONE      = 3'd4;

    reg [2:0] state, next_state;


        always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if ( first_word_arrived) next_state = RECEIVING;
            RECEIVING: if (rts_rising)          next_state = STREAM;
            STREAM:    if (stream_done)         next_state = WAIT_CAP;
            WAIT_CAP:  if (capture_finished)    next_state = DONE;
            DONE: next_state = IDLE;
            default:     next_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end


    always @(posedge clk) begin
        if (rst) begin
            cts            <= 1'b1;   
            total_words    <= 0;
            stream_enable  <= 1'b0;
            batch_clear    <= 1'b0;
        end else begin
            batch_clear <= 1'b0;  

            case (state)
                IDLE: begin
                    cts           <= 1'b1;
                    stream_enable <= 1'b0;
                    if (next_state == RECEIVING)
                        t_upload_start <= counter_val;
                end

                RECEIVING: begin
                    cts <= 1'b1;   // still accepting bytes from the PC
                    if (next_state == STREAM) begin
                        total_words   <= word_count_live;  // freeze the valid count
                        cts           <= 1'b0;              // stop accepting new bytes
                        t_buffer_full <= counter_val;
                    end
                end

                STREAM: begin
                    cts           <= 1'b0;
                    stream_enable <= 1'b1;
                    if (next_state == WAIT_CAP)
                        t_stream_done <= counter_val;
                end

                WAIT_CAP: begin
                    stream_enable <= 1'b0;   // all words already pushed
                    if (next_state == DONE)
                        t_capture_done <= counter_val;
                end

                DONE: begin
                    if (next_state == IDLE)
                        batch_clear <= 1'b1;   // one-cycle pulse: reset psa_new's counters
                end

                default: ;
            endcase
        end
    end
endmodule