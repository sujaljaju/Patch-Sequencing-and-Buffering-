module top_module #(
    parameter integer NUM_WORDS = 80,
    parameter integer ADDR_WIDTH = $clog2(NUM_WORDS),
    parameter integer DATA_WIDTH = 32
)(
    input  clk,
    input  reset,
    input  rx,
    input  [15:0] sw,     // sw[15:14]=LED mux, sw[13]=Profiler Mode, sw[6:0]=Address (sw[3:0]=Profiler Channel when in profiler mode)
    input  rst_view_btn,  
    output tx,
    output [7:0] anode,
    output [6:0] seg,
    output [15:0] led 
);

    wire [(NUM_WORDS*DATA_WIDTH)-1:0] data_out_interconnect;
    wire push_interconnect;
    wire ready_interconnect;
    wire output_enable_interconnect; 
    wire [(NUM_WORDS*DATA_WIDTH)-1:0] parallel_read_data; 
    wire gca_eoc; 

    // LED Multiplexer Wires
    wire [15:0] psa_leds;
    wire [15:0] sipo_leds;
    wire [15:0] gca_leds;

    assign led = (sw[15:14] == 2'b10) ? gca_leds :
                 (sw[15:14] == 2'b01) ? sipo_leds : 
                 psa_leds;

    // ================================================================
    // HARDWARE PROFILER
    // free_counter is 32-bit, ticking every clock (10 ns @ 100 MHz).
    // Every raw timestamp/duration value below is in units of clock
    // ticks -- multiply by 10 ns to get real time for your timing
    // diagram. Select which value to view on the 7-segment display via
    // sw[13]=1 (profiler mode) and sw[3:0] (channel select, see the
    // list below the mux at the bottom of this block).
    // ================================================================

    reg [31:0] free_counter;
    always @(posedge clk) begin
        if (reset) free_counter <= 32'd0;
        else       free_counter <= free_counter + 1'b1;
    end

    // ---------------- Rise/fall timestamps for the 4 key handshake signals ----------------
    reg push_d, oe_d, eoc_d, ready_d;
    reg [31:0] ts_push_rise,  ts_push_fall;
    reg [31:0] ts_oe_rise,    ts_oe_fall;
    reg [31:0] ts_eoc_rise,   ts_eoc_fall;
    reg [31:0] ts_ready_rise, ts_ready_fall;

    always @(posedge clk) begin
        if (reset) begin
            push_d <= 1'b0; oe_d <= 1'b0; eoc_d <= 1'b0; ready_d <= 1'b0;
            ts_push_rise  <= 0; ts_push_fall  <= 0;
            ts_oe_rise    <= 0; ts_oe_fall    <= 0;
            ts_eoc_rise   <= 0; ts_eoc_fall   <= 0;
            ts_ready_rise <= 0; ts_ready_fall <= 0;
        end else begin
            push_d  <= push_interconnect;
            oe_d    <= output_enable_interconnect;
            eoc_d   <= gca_eoc;
            ready_d <= ready_interconnect;

            if (push_interconnect  && !push_d)  ts_push_rise  <= free_counter;
            if (!push_interconnect && push_d)   ts_push_fall  <= free_counter;

            if (output_enable_interconnect  && !oe_d) ts_oe_rise <= free_counter;
            if (!output_enable_interconnect && oe_d)  ts_oe_fall <= free_counter;

            if (gca_eoc  && !eoc_d) ts_eoc_rise <= free_counter;
            if (!gca_eoc && eoc_d)  ts_eoc_fall <= free_counter;

            if (ready_interconnect  && !ready_d) ts_ready_rise <= free_counter;
            if (!ready_interconnect && ready_d)  ts_ready_fall <= free_counter;
        end
    end

    // ---------------- Phase durations: enter/exit each FSM phase, compute the delta ----------------
    // Read directly from the submodules' own state registers (hierarchical
    // reference -- standard, synthesizable in Vivado for read-only debug/
    // profiling signals like this) so no new ports are needed on psa/sipo/gca.
    localparam PSA_RECEIVE_DATA = 5'd3;   // matches psa.v's localparam
    localparam PSA_STREAM_DATA  = 5'd8;   // matches psa.v's localparam
    localparam SIPO_GET_DATA    = 2'd1;   // matches sipo.v's localparam
    localparam SIPO_SEND_DATA   = 2'd2;   // matches sipo.v's localparam

    reg [4:0] psa_state_d;
    reg [1:0] sipo_state_d;

    reg [31:0] t_rx_enter,       rx_data_duration;      // PSA: RECEIVE_DATA  (PC -> PSA, UART byte reception)
    reg [31:0] t_stream_enter,   stream_duration;       // PSA: STREAM_DATA   (PSA -> SIPO, pushing buffered words -- "transmit")
    reg [31:0] t_getdata_enter,  sipo_fill_duration;     // SIPO: GET_DATA     (SIPO's own view of receiving pushed words)
    reg [31:0] t_senddata_enter, sipo_send_duration;     // SIPO: SEND_DATA    (SIPO -> GCA handoff)

    always @(posedge clk) begin
        if (reset) begin
            psa_state_d  <= 5'd0;
            sipo_state_d <= 2'd0;
            t_rx_enter <= 0; rx_data_duration <= 0;
            t_stream_enter <= 0; stream_duration <= 0;
            t_getdata_enter <= 0; sipo_fill_duration <= 0;
            t_senddata_enter <= 0; sipo_send_duration <= 0;
        end else begin
            psa_state_d  <= psa_inst.state;
            sipo_state_d <= sipo_inst.state;

            // PSA RECEIVE_DATA: how long PSA took to take in the payload over UART
            if (psa_inst.state == PSA_RECEIVE_DATA && psa_state_d != PSA_RECEIVE_DATA)
                t_rx_enter <= free_counter;
            if (psa_inst.state != PSA_RECEIVE_DATA && psa_state_d == PSA_RECEIVE_DATA)
                rx_data_duration <= free_counter - t_rx_enter;

            // PSA STREAM_DATA: how long PSA took to push the buffered words into SIPO ("transmit")
            if (psa_inst.state == PSA_STREAM_DATA && psa_state_d != PSA_STREAM_DATA)
                t_stream_enter <= free_counter;
            if (psa_inst.state != PSA_STREAM_DATA && psa_state_d == PSA_STREAM_DATA)
                stream_duration <= free_counter - t_stream_enter;

            // SIPO GET_DATA: how long SIPO took to take in (shift in) the pushed words
            if (sipo_inst.state == SIPO_GET_DATA && sipo_state_d != SIPO_GET_DATA)
                t_getdata_enter <= free_counter;
            if (sipo_inst.state != SIPO_GET_DATA && sipo_state_d == SIPO_GET_DATA)
                sipo_fill_duration <= free_counter - t_getdata_enter;

            // SIPO SEND_DATA: how long the SIPO -> GCA handoff took
            if (sipo_inst.state == SIPO_SEND_DATA && sipo_state_d != SIPO_SEND_DATA)
                t_senddata_enter <= free_counter;
            if (sipo_inst.state != SIPO_SEND_DATA && sipo_state_d == SIPO_SEND_DATA)
                sipo_send_duration <= free_counter - t_senddata_enter;
        end
    end

    // ---------------- Profiler channel select (sw[3:0], active when sw[13]=1) ----------------
    // 0: free_counter (live)         8: ts_ready_fall
    // 1: ts_push_rise                9: rx_data_duration    <- "PSA data-in time"
    // 2: ts_push_fall               10: stream_duration     <- "PSA->SIPO transmit time"
    // 3: ts_oe_rise                 11: sipo_fill_duration  <- "SIPO data-in time"
    // 4: ts_oe_fall                 12: sipo_send_duration  <- "SIPO->GCA transmit time"
    // 5: ts_eoc_rise                13: psa_inst.state  (live, zero-extended)
    // 6: ts_eoc_fall                14: sipo_inst.state (live, zero-extended)
    // 7: ts_ready_rise              15: gca_inst.state  (live, zero-extended)
    wire [31:0] profiler_data =
        (sw[3:0] == 4'd0)  ? free_counter                          :
        (sw[3:0] == 4'd1)  ? ts_push_rise                          :
        (sw[3:0] == 4'd2)  ? ts_push_fall                          :
        (sw[3:0] == 4'd3)  ? ts_oe_rise                            :
        (sw[3:0] == 4'd4)  ? ts_oe_fall                            :
        (sw[3:0] == 4'd5)  ? ts_eoc_rise                           :
        (sw[3:0] == 4'd6)  ? ts_eoc_fall                           :
        (sw[3:0] == 4'd7)  ? ts_ready_rise                         :
        (sw[3:0] == 4'd8)  ? ts_ready_fall                         :
        (sw[3:0] == 4'd9)  ? rx_data_duration                      :
        (sw[3:0] == 4'd10) ? stream_duration                       :
        (sw[3:0] == 4'd11) ? sipo_fill_duration                    :
        (sw[3:0] == 4'd12) ? sipo_send_duration                    :
        (sw[3:0] == 4'd13) ? {27'd0, psa_inst.state}                :
        (sw[3:0] == 4'd14) ? {30'd0, sipo_inst.state}               :
        (sw[3:0] == 4'd15) ? {30'd0, gca_inst.state}                :
        32'hFFFFFFFF;

    // ================================================================
    // MODULE INSTANTIATIONS (unchanged)
    // ================================================================

    psa #(
        .data_width(DATA_WIDTH),
        .NUM_WORDS(NUM_WORDS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) psa_inst (
        .clk(clk),                       
        .rx(rx),                        
        .reset(reset),                     
        .ready(ready_interconnect),  
        .tx(tx),                       
        .led(psa_leds),              
        .data_out(data_out_interconnect),     
        .push(push_interconnect)              
    );

    SIPO_buffer #(
        .data_width(DATA_WIDTH),
        .slots(NUM_WORDS),
        .word_count_width(ADDR_WIDTH)
    ) sipo_inst (
        .clk(clk),
        .rst(reset),
        .write_data(data_out_interconnect),   
        .push(push_interconnect),             
        .eoc(gca_eoc),                         
        .read_data(parallel_read_data),       
        .output_enable(output_enable_interconnect), 
        .ready(ready_interconnect),           
        .led(sipo_leds)                       
    );

    gca #(
        .data_width(DATA_WIDTH),
        .slots(NUM_WORDS),
        .word_count_width(ADDR_WIDTH)
    ) gca_inst (
        .clk(clk),
        .rst(reset),
        .button_edge(rst_view_btn),               
        .input_enable(output_enable_interconnect), 
        .sw(sw[ADDR_WIDTH-1:0]),
        .profiler_mode(sw[13]),
        .profiler_data(profiler_data),
        .read_data(parallel_read_data),       
        .eoc(gca_eoc),                         
        .anode(anode),                        
        .seg(seg),                            
        .led(gca_leds)
    );

endmodule