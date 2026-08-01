module lfsr #(
    parameter integer patches = 25,  
    parameter integer data_width = 32,
    parameter [data_width-1:0] seed = 32'h1234_5678,
    parameter integer clock = 10,
    parameter integer patch_period_ns = 1000000,
    parameter counter_width = $clog2(patch_period_ns/clock)) 
)(
    input wire clk,
    input wire rst,
    output reg [data_width-1:0] data_out,
    output reg done
);

    reg [$clog2(patches)-1:0] patch_count;


    always @(posedge clk) begin
        if (rst) begin
            data_out <= seed; // Reset to the seed value
            counter <= {counter_width{1'b0}}; //reset the counter to zero
        end else if (counter < time_ns/clock) begin
            counter <= counter + 1;
        
        end else begin
            // LFSR logic for generating pseudo-random numbers
            data_out <= {data_out[data_width-2:0], data_out[data_width-1] ^ data_out[data_width-11] ^ data_out[data_width-31] ^ data_out[data_width-32]};
        end
    end
        

endmodule
