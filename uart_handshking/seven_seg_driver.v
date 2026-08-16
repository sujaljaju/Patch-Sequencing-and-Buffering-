module seven_seg_drive(
    input clk,
    input [31:0] data_in,
    output reg [7:0] anode,
    output reg [6:0] seg
);
    
    // Wire to hold the converted BCD digits (10 digits total)
    wire [39:0] bcd_data;
    
    // Convert Binary to BCD
    bin2bcd bcd_converter (
        .bin(data_in),
        .bcd(bcd_data)
    );

    // Refresh counter to multiplex the displays (~1 kHz refresh rate)
    reg [19:0] refresh_counter = 0;
    wire [2:0] LED_activating_counter; 
    
    always @(posedge clk) begin
        refresh_counter <= refresh_counter + 1;
    end
    
    assign LED_activating_counter = refresh_counter[19:17];
    
    reg [3:0] current_digit;
    reg out_of_bounds;
    
    // Anode selection (Active Low) - We only display the lower 8 BCD digits
    always @(*) begin
        // Check if top module is outputting the FFFFFFFF error code
        out_of_bounds = (data_in == 32'hFFFFFFFF); 
        
        case(LED_activating_counter)
            3'b000: begin anode = 8'b11111110; current_digit = bcd_data[3:0];   end // Digit 0 (Rightmost)
            3'b001: begin anode = 8'b11111101; current_digit = bcd_data[7:4];   end // Digit 1
            3'b010: begin anode = 8'b11111011; current_digit = bcd_data[11:8];  end // Digit 2
            3'b011: begin anode = 8'b11110111; current_digit = bcd_data[15:12]; end // Digit 3
            3'b100: begin anode = 8'b11101111; current_digit = bcd_data[19:16]; end // Digit 4
            3'b101: begin anode = 8'b11011111; current_digit = bcd_data[23:20]; end // Digit 5
            3'b110: begin anode = 8'b10111111; current_digit = bcd_data[27:24]; end // Digit 6
            3'b111: begin anode = 8'b01111111; current_digit = bcd_data[31:28]; end // Digit 7 (Leftmost)
        endcase
    end
    
    // Cathode patterns (Active Low for Nexys A7)
    always @(*) begin
        if (out_of_bounds) begin
            // Display a dash '-' if the switch address is empty/invalid
            seg = 7'b0111111; 
        end else begin
            // Display standard numbers 0-9
            case(current_digit)
                4'h0: seg = 7'b1000000; 
                4'h1: seg = 7'b1111001; 
                4'h2: seg = 7'b0100100; 
                4'h3: seg = 7'b0110000; 
                4'h4: seg = 7'b0011001; 
                4'h5: seg = 7'b0010010; 
                4'h6: seg = 7'b0000010; 
                4'h7: seg = 7'b1111000; 
                4'h8: seg = 7'b0000000; 
                4'h9: seg = 7'b0010000; 
                default: seg = 7'b1111111; // Blank if error
            endcase
        end
    end
endmodule