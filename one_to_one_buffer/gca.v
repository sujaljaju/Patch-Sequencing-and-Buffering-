module gca#(
    parameter integer data_width = 32,
    parameter integer slots = 80,
    parameter integer word_count_width = $clog2(slots)
)
(input clk,
input rst,
input button_edge, 
input input_enable, //from sipo
input profiler_mode,
input [31:0] profiler_data,
input [word_count_width-1:0] sw,
input [(slots*data_width-1):0] read_data,
output reg eoc,
output [7:0] anode,
output [6:0] seg,
output [15:0] led);

localparam IDLE          = 2'd0;
localparam SEND_EOC      = 2'd1;
localparam CAPTURE_DATA  = 2'd2;
localparam VIEW_DATA     = 2'd3;

reg [1:0] state;
reg [data_width-1:0] mem_gca [0:slots-1];

// --- 10ms Mechanical Debouncer & Edge Detector ---
    reg [19:0] bounce_timer;
    reg btn_debounced;
    reg btn_prev;

    always @(posedge clk) begin
        if (rst) begin
            bounce_timer <= 0;
            btn_debounced <= 0;
            btn_prev <= 0;
        end else begin
            if (button_edge == 1'b1) begin
                if (bounce_timer < 20'd1000000)
                    bounce_timer <= bounce_timer + 1'b1;
                else
                    btn_debounced <= 1'b1;
            end else begin
                bounce_timer <= 0;
                btn_debounced <= 1'b0;
            end
            btn_prev <= btn_debounced;
        end
    end

    wire btn_pulse = btn_debounced && !btn_prev;

// input_enable must be observed high for 3 consecutive cycles before it's
// trusted enough to even START the handshake -- protects against a single-
// cycle glitch/spurious pulse on input_enable being mistaken for a real
// batch-ready signal. Note: && input_enable guards against ie_stable_cnt
// still reading its old saturated value for one extra cycle right after
// input_enable has already dropped, before its own reset takes effect.
reg [1:0] ie_stable_cnt;
wire ie_confirmed = (ie_stable_cnt == 1'd1) && input_enable;
always @(posedge clk) begin
    if (rst) begin
        ie_stable_cnt <= 0;
    end else if (input_enable) begin
        if (ie_stable_cnt < 1'd1) ie_stable_cnt <= ie_stable_cnt + 1'b1;
    end else begin
        ie_stable_cnt <= 0;
    end
end

// eoc must stay high for >=3 consecutive cycles so SIPO's OWN
// eoc_confirmed (which needs 3 confirmed cycles on ITS side) actually
// has time to become true and let it perform its mem[]->read_data copy.
reg [1:0] hold_cnt;

// Detect output_enable's FALLING edge -- that's the one cycle SIPO
// guarantees read_data holds the freshly-copied batch (SIPO copies
// mem[]->read_data on the SAME edge it drops back to IDLE, so read_data
// is only trustworthy from that edge onward).
reg input_enable_d;
always @(posedge clk) begin
    if (rst) input_enable_d <= 1'b0;
    else     input_enable_d <= input_enable;
end
wire input_enable_falling = input_enable_d && !input_enable;

integer i;
always @(posedge clk) begin
    if (rst) begin
        state    <= IDLE;
        eoc      <= 1'b0;
        hold_cnt <= 0;
        for (i = 0; i < slots; i = i + 1)
            mem_gca[i] <= {data_width{1'b0}};
    end else begin
        case (state)

            IDLE: begin
                eoc      <= 1'b0;
                hold_cnt <= 0;
                if (ie_confirmed) begin
                    state <= SEND_EOC;
                end
            end

            SEND_EOC: begin
                eoc <= 1'b1;
                if (hold_cnt < 2'd2) begin
                    hold_cnt <= hold_cnt + 1'b1;
                end else begin
                    state <= CAPTURE_DATA;
                end
            end

            CAPTURE_DATA: begin
                eoc <= 1'b1; // keep asserting -- SIPO is still working through its copy+return-to-IDLE
                if (input_enable_falling) begin
                    for (i = 0; i < slots; i = i + 1)
                        mem_gca[i] <= read_data[(i*data_width) +: data_width];
                    eoc   <= 1'b0;
                    state <= VIEW_DATA;
                end
            end

            VIEW_DATA: begin
                eoc <= 1'b0; // not ready for a new batch until the user clears this one
                if (btn_pulse) begin 
                    state <= IDLE;
                    for (i = 0; i < slots; i = i + 1)
                        mem_gca[i] <= {data_width{1'b0}};
                end
            end

            default: begin
                state <= IDLE;
                eoc   <= 1'b0;
            end
        endcase
    end
end

// LED Mapping
assign led[0] = (state == IDLE);
assign led[1] = (state == SEND_EOC);
assign led[2] = (state == CAPTURE_DATA);
assign led[3] = (state == VIEW_DATA);
assign led[4] = input_enable;
assign led[5] = input_enable_falling;
assign led[6] = eoc;
assign led[7] = ie_confirmed;
assign led[15:8] = 8'b0;

reg [data_width-1:0] display_data;
    always @(*) begin
        if (profiler_mode) begin
            display_data = profiler_data;
        end else if (sw < slots) begin
            display_data = mem_gca[sw];
        end else begin
            display_data = 32'hFFFFFFFF; 
        end
    end

seven_seg_drive display_inst (
    .clk(clk),
    .data_in(display_data),
    .anode(anode),
    .seg(seg)
);      

endmodule