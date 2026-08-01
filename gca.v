module gca#(
)
(
input [(slots*data_width-1):0] read_data,
output reg [(slots*data_width-1):0] serial_data ,
)

genvar k;
generate
    for (k = 0; k < slots ; k = k + 1) begin : read_data_gen
        assign serial_data[(k+1)*data_width-1:k*data_width] =  read_data[(k+1)*data_width-1:k*data_width]; //assigning the data from the buffer to the output
    end
endgenerate
    






















    //module top(input clk,rst
    //output reg [31:0] data_out );


//endmodule