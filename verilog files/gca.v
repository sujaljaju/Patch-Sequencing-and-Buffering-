module gca #(
    parameter integer data_width = 32,
    parameter integer slots = 80
)(
    input clk,
    input input_enable,
    input [(slots*data_width-1):0] read_data,
    output reg eoc,
    output reg [(slots*data_width-1):0] serial_data
);

    reg [1:0] oe_stable_cnt;
    reg [6:0] delay_counter;

    wire oe_confirmed_now =
        (oe_stable_cnt == 2'd2) && input_enable;

    localparam IDLE      = 2'd0;
    localparam WAIT_1US  = 2'd1;
    localparam EOC_STATE = 2'd2;

    reg [1:0] state;

    always @(posedge clk) begin

        eoc <= 1'b0;

        if (!input_enable) begin
            oe_stable_cnt <= 2'd0;
            delay_counter <= 7'd0;
            state <= IDLE;
        end

        else begin

            if (oe_stable_cnt < 2'd2)
                oe_stable_cnt <= oe_stable_cnt + 1'b1;

            case (state)

                IDLE: begin
                    if (oe_confirmed_now) begin
                        serial_data <= read_data[(slots*data_width-1):0];
                        delay_counter <= 7'd0;
                        state <= WAIT_1US;
                    end
                end

                WAIT_1US: begin
                    if (delay_counter < 7'd99) begin
                        delay_counter <= delay_counter + 1'b1;
                    end
                    else begin
                        delay_counter <= 7'd0;
                        state <= EOC_STATE;
                    end
                end

                EOC_STATE: begin
                    eoc <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    delay_counter <= 7'd0;
                end

            endcase
        end
    end

endmodule