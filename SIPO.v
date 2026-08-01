module SIPO_buffer#(
parameter integer data_width = 32,
parameter integer slots =25,  
//parameter integer control_width = 7,
parameter  clock = 10, //ns
parameter  time_ns = 25000000, //ns
parameter counter_width = $clog2(time_ns/clock)) 
(input clk,
input rst,
input [data_width-1:0] write_data,
output wire [(slots*data_width-1):0] read_data,
output wire read_enable); 
// what we have to is fill mem[i+1] with mem[i] at each posedge
//the sipo buffer has N input lines that take M clock cycles to send the data 
reg [data_width-1:0] mem [0:slots-1]; //array of memory in the buffer
reg [counter_width-1:0] counter = {counter_width{1'b0}}; //counter to count the number of clock cycles

assign read_enable = (counter == (time_ns/clock)-1);
integer i;
always @(posedge clk) begin
    if(rst) begin
        counter <= {counter_width{1'b0}}; //reset the counter to zero
        for (i = 0; i < slots; i = i + 1)
            mem[i] <= {data_width{1'b0}}; //reset the buffer, so memory is all zeros
    end else if (counter < time_ns/clock) begin
        counter <= counter + 1;
        for (i = slots-1; i >0; i = i - 1) begin
            mem[i] <= mem[i-1];   //shifting the data in the buffer to the right
        end
        mem[0] <= write_data;   //writing the new data to the first slot of the buffer
    end 
    else begin
        counter <= {counter_width{1'b0}}; //reset the counter to zero
    end
end
genvar j;
generate
    for (j = 0; j < slots; j = j + 1) begin : read_data_gen
        assign read_data[(j+1)*data_width-1:j*data_width] = read_enable ? mem[j] : {data_width{1'b0}}; //assigning the data from the buffer to the output
    end
endgenerate
endmodule
