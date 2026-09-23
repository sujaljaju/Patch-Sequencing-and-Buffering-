module SIPO_buffer#(
    parameter integer data_width       = 32,
    parameter integer slots            = 80,
    parameter integer word_count_width = $clog2(slots)
)(
    input  clk,
    input  rst,
    input  [slots*data_width-1:0] write_data,
    input  push,          // from psa        
    input  eoc,           // from gca       
    output reg [(slots*data_width-1):0] read_data,
    output reg output_enable,  //to gca
    output reg ready,          //to psa
    output [15:0] led // LED debugging output
);

    localparam IDLE = 2'd0;
    localparam GET_DATA = 2'd1;
    localparam SEND_DATA = 2'd2;

    reg [1:0] state = IDLE;

    reg [data_width-1:0] mem [0:slots-1];
    reg [word_count_width-1:0] loaded_words = 0;

    integer j;
    integer i;

    reg [1:0] push_stable_cnt = 0;
    wire push_confirmed = (push_stable_cnt == 1'd1);
    always @(posedge clk) begin
        if (rst) begin
            push_stable_cnt <= 0;
        end else if (push) begin
            if (push_stable_cnt < 1'd1) push_stable_cnt <= push_stable_cnt + 1'b1; 
        end else begin
            push_stable_cnt <= 0;
        end
    end

    reg [1:0] eoc_stable_cnt = 0;
    wire eoc_confirmed = (eoc_stable_cnt == 1'd1);
    always @(posedge clk) begin
        if (rst) begin
            eoc_stable_cnt <= 0;
        end else if (eoc) begin
            if (eoc_stable_cnt < 1'd1) eoc_stable_cnt <= eoc_stable_cnt + 1'b1;
        end else begin
            eoc_stable_cnt <= 0;
        end
    end

    wire batch_trigger = (loaded_words != 0);
    wire ready_trigger = (loaded_words == 0);

    always @(posedge clk) begin
        if (rst) begin
            loaded_words  <= 0;
            output_enable <= 1'b0;
            state         <= IDLE;
            ready         <= 1'b1;
            
            for (i = 0; i < slots; i = i + 1)
                mem[i] <= {data_width{1'b0}};

        end else begin

            case (state)
                IDLE: begin
                    loaded_words <= 0;
                    ready <= 1'b1;
                    output_enable <= 1'b0;
                    if (push_confirmed && ready_trigger) begin
                        // Flush residual data from previous batches
                        for (i = 0; i < slots; i = i + 1) begin
                            mem[i] <= {data_width{1'b0}};
                        end
                        
                        state <= GET_DATA; 
                    end else begin
                        state <= IDLE;
                    end
                end

                GET_DATA: begin
                    if (push_confirmed) begin
                        for (i = 0; i < slots; i = i + 1) begin
                            mem[i] <= write_data[(i*data_width) +: data_width];
                        end
                            loaded_words <= loaded_words + 1'b1;
                        if (batch_trigger) begin
                            state <= SEND_DATA;
                            ready <= 1'b0;
                            output_enable <= 1'b1;
                        end 
                    end 
                end

                SEND_DATA: begin
                    if (batch_trigger && eoc_confirmed) begin
                        // FIX: bound was `loaded_words` (== total_words-1, frozen
                        // when batch_trigger fired), which dropped the final word
                        // every batch. Use total_words so all words are copied.
                        for (j = 0; j < slots; j = j + 1) begin
                            read_data[j*data_width +: data_width] <= mem[j];
                        end
                        state <= IDLE;
                        loaded_words <= 0;
                    end 
                    else begin
                        state <= SEND_DATA;
                        ready <= 1'b0;
                        output_enable <= 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

    // --- LED DEBUGGING LOGIC ---
    assign led[0] = (state == IDLE);
    assign led[1] = (state == GET_DATA);
    assign led[2] = (state == SEND_DATA);
    assign led[3] = push_confirmed;
    assign led[4] = eoc_confirmed;
    assign led[5] = batch_trigger;
    assign led[6] = ready_trigger;
    assign led[7] = ready;
    assign led[8] = output_enable;
    assign led[9] = eoc;
    assign led[15:10] = 7'b0; // Unused LEDs kept off


endmodule