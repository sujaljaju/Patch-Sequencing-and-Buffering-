module SIPO_buffer#(
parameter integer data_width = 32,
parameter integer slots =25,  // number of slots in the buffer
parameter integer control_width = 7) //

(input clk,
input rst,
input write_enable,
input [data_width-1:0] write_data,
input read_enable,
output reg [(slots*data_width-1):0] read_data);
// what we have to is fill mem[i+1] with mem[i] at each posedge
//the sipo buffer has N input lines that take M clock cycles to send the data 
reg [data_width-1:0] mem [0:slots-1]; //array of memory in the buffer
integer i;

always @(posedge clk) begin
    if(rst) begin
        for (i = 0; i < slots; i = i + 1)
            mem[i] <= {data_width{1'b0}}; //reset the buffer, so memory is all zeros

    end else if (write_enable) begin
        for (i = slots-1; i >0; i = i - 1) begin
            mem[i] <= mem[i-1];   //shifting the data in the buffer to the right
        end
        mem[0] <= write_data;   //writing the new data to the first slot of the buffer

    end else if (read_enable) begin
        for (i = 0; i < slots ; i = i+1)
            read_data <= mem [i];
    end
end
endmodule
