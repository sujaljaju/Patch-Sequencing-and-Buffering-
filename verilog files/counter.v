module counter #(
    parameter integer COUNTER_WIDTH = 32
) (
    input clk,
    input rst,
    input output_enable,
    input eoc,
    input push,
    input ready,
    output reg [COUNTER_WIDTH-1:0] counter_val,
    output reg [COUNTER_WIDTH-1:0] output_enable_time,
    output reg [COUNTER_WIDTH-1:0] eoc_time,
    output reg [COUNTER_WIDTH-1:0] push_time,
    output reg [COUNTER_WIDTH-1:0] ready_time,
    output reg [COUNTER_WIDTH-1:0] output_enable_low_time,
    output reg [COUNTER_WIDTH-1:0] eoc_low_time,
    output reg [COUNTER_WIDTH-1:0] push_low_time,
    output reg [COUNTER_WIDTH-1:0] ready_low_time
);
    // Registered signals for rising edge detection
    reg output_enable_d;
    reg eoc_d;
    reg push_d;
    reg ready_d;

    // Free-running clock cycle counter
    always @(posedge clk) begin
        if (rst) begin
            counter_val <= {COUNTER_WIDTH{1'b0}};
        end else begin
            counter_val <= counter_val + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            output_enable_d <= 1'b0;
            eoc_d <= 1'b0;
            push_d <= 1'b0;
            ready_d <= 1'b0;
        end else begin
            output_enable_d <= output_enable;
            eoc_d <= eoc;
            push_d <= push;
            ready_d <= ready;
        end
    end

    // Capture timestamp directly on rising edge (0 -> 1 transition)
    always @(posedge clk) begin
        if (rst) begin
            output_enable_time <= {COUNTER_WIDTH{1'b0}};
            eoc_time <= {COUNTER_WIDTH{1'b0}};
            push_time <= {COUNTER_WIDTH{1'b0}};
            ready_time <= {COUNTER_WIDTH{1'b0}};
            output_enable_low_time <= {COUNTER_WIDTH{1'b0}};
            eoc_low_time <= {COUNTER_WIDTH{1'b0}};
            push_low_time <= {COUNTER_WIDTH{1'b0}};
            ready_low_time <= {COUNTER_WIDTH{1'b0}};
        end else begin
            // Capture timestamp on falling edge (0 to 1 transition)
            if (output_enable && !output_enable_d) output_enable_time <= counter_val;
            if (eoc && !eoc_d) eoc_time <= counter_val;
            if (push && !push_d) push_time <= counter_val;
            if (ready && !ready_d) ready_time <= counter_val;
            // Capture timestamp on falling edge (1 to 0 transition)
            if (!output_enable && output_enable_d) output_enable_low_time <= counter_val;
            if (!eoc && eoc_d) eoc_low_time <= counter_val;
            if (!push && push_d) push_low_time <= counter_val;
            if (!ready && ready_d) ready_low_time <= counter_val;
        end
    end

endmodule
