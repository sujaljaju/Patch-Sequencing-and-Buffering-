module bin2bcd(
    input [31:0] bin,
    output reg [39:0] bcd // 10 decimal digits (4 bits per digit)
);
    
    integer i, j;
    
    always @(*) begin
        // Initialize BCD to zero
        bcd = 40'd0;
        
        // Shift and Add 3 Algorithm
        for (i = 31; i >= 0; i = i - 1) begin
            
            // Check if any BCD digit is >= 5. If so, add 3
            for (j = 0; j < 10; j = j + 1) begin
                if (bcd[j*4 +: 4] >= 5) begin
                    bcd[j*4 +: 4] = bcd[j*4 +: 4] + 3;
                end
            end
            
            // Shift left by 1
            bcd = {bcd[38:0], bin[i]};
        end
    end
    
endmodule