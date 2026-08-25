module SIPO_buffer#(
    parameter integer data_width       = 32,
    parameter integer slots            = 80,
    parameter integer word_count_width = $clog2(slots+1)
)(
    input  clk,
    input  rst,
    input  [data_width-1:0] write_data,
    input  input_enable,          // "push" from psa_new
    input  [word_count_width-1:0] word_count,
    input  eoc,                   // from GCA
    output [(slots*data_width-1):0] read_data,
    output reg output_enable,
    output reg ready
);

    reg [data_width-1:0] mem [0:slots-1];
    reg [word_count_width-1:0] loaded_words;
    integer i;

    reg [1:0] push_stable_cnt;
    wire push_confirmed = (push_stable_cnt == 2'd2);
    always @(posedge clk) begin
        if (rst) begin
            push_stable_cnt <= 0;
        end else if (input_enable) begin
            if (push_stable_cnt < 2'd2) push_stable_cnt <= push_stable_cnt + 1'b1; 
        end else begin
            push_stable_cnt <= 0;
        end
    end

    reg [1:0] eoc_stable_cnt;
    always @(posedge clk) begin
        if (rst) begin
            eoc_stable_cnt <= 0;
        end else if (eoc) begin
            if (eoc_stable_cnt < 2'd2) eoc_stable_cnt <= eoc_stable_cnt + 1'b1;
        end else begin
            eoc_stable_cnt <= 0;
        end
    end
    
    assign ready = (eoc_stable_cnt == 2'd2)?1:0;

    reg [1:0] oe_hold;
    wire batch_trigger = push_confirmed && (loaded_words == word_count - 1);

    always @(posedge clk) begin
        if (rst) begin
            loaded_words  <= 0;
            output_enable <= 1'b0;
            oe_hold       <= 0;
            for (i = 0; i < slots; i = i + 1)
                mem[i] <= {data_width{1'b0}};
        end else begin
            if (push_confirmed) begin
                // Shift existing data right and write incoming word to mem[0]
                for (i = word_count-1; i > 0; i = i - 1)
                    mem[i] <= mem[i-1];
                mem[0] <= write_data;

                if (!batch_trigger)
                    loaded_words <= loaded_words + 1'b1;
                else
                    loaded_words <= 0;   // ready to count the next batch from zero
            end

            if (batch_trigger) begin
                oe_hold       <= 2'd2;   // hold output_enable for 3 cycles total
                output_enable <= 1'b1;
            end else if (oe_hold != 0) begin
                oe_hold       <= oe_hold - 1'b1;
                output_enable <= 1'b1;
            end else begin
                output_enable <= 1'b0;
            end
        end
    end

    genvar j;
    generate
        for (j = 0; j < slots; j = j + 1) begin : read_data_gen
            assign read_data[(j+1)*data_width-1 : j*data_width] = mem[j];
        end
    endgenerate

endmodule
//removed input_enable from the if statement in the always block to allow for the output_enable to be asserted even if input_enable is not high. This change allows for the output_enable signal to be held high for 3 cycles after the last word of a batch has been received, regardless of whether input_enable is still high or not.
//changed the for loop final count to word_count-1 to ensure that the last word of the batch is written to mem[0] and not shifted out of the buffer. This change ensures that the last word of a batch is always available for output, even if it is the only word in the batch.