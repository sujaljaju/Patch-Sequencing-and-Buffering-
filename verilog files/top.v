module top (
    input  clk,
    input  rst,
    input  rx,
    output reg  [31:0] data_out,
    output rx_done,
    output [31:0] counter_val,
    output [31:0] output_enable_time,
    output [31:0] eoc_time,
    output [31:0] push_time,
    output [31:0] ready_time
);

    parameter integer data_width = 32;
    parameter integer slots      = 25;
    parameter integer clock_ns   = 10;
    parameter integer period_ns  = 25000;
    parameter integer CLOCK_FREQ = 1000000000 / (clock_ns); // 100 MHz for 10ns
    parameter integer BAUD_RATE  = 115200;

    // UART RX wires
    wire [31:0] uart_data_out;
    wire        uart_data_ready;
    wire        uart_valid;

    // PSA wires
    wire [data_width-1:0] psa_data_out;
    wire psa_push;

    // SIPO wires
    wire [(slots*data_width-1):0] sipo_read_data;
    wire sipo_output_enable;
    wire sipo_ready;

    // GCA wires
    wire gca_eoc;
    wire [(data_width-1):0] gca_serial_data;

    // Instantiate UART Receiver
    uart_rx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .clk(clk),
        .rst(rst),
        .rx(rx),
        .valid(uart_valid),
        .data_out(uart_data_out),
        .data_ready(uart_data_ready)
    );

    // Instantiate PSA (buffers UART data and streams to SIPO)
    psa #(
        .clock_ns(clock_ns),
        .period_ns(period_ns),
        .data_Width(data_width),
        .num_values(slots)
    ) u_psa (
        .clk(clk),
        .rst(rst),
        .ready(sipo_ready),
        .uart_data(uart_data_out),
        .uart_data_ready(uart_data_ready),
        .data_out(psa_data_out),
        .push(psa_push),
        .rx_done(rx_done)
    );

    // Instantiate SIPO Buffer
    SIPO_buffer #(
        .data_width(data_width),
        .slots(slots),
        .clock(clock_ns),
        .time_ns(period_ns)
    ) u_sipo (
        .clk(clk),
        .rst(rst),
        .write_data(psa_data_out),
        .input_enable(psa_push),
        .eoc(gca_eoc),
        .read_data(sipo_read_data),
        .output_enable(sipo_output_enable),
        .ready(sipo_ready)
    );

    // Instantiate GCA
    gca #(
        .data_width(data_width),
        .slots(slots)
    ) u_gca (
        .clk(clk),
        .input_enable(sipo_output_enable),
        .read_data(sipo_read_data),
        .eoc(gca_eoc),
        .serial_data(gca_serial_data)
    );

    // Instantiate Timestamp Counter
    counter #(
        .COUNTER_WIDTH(32)
    ) u_counter (
        .clk(clk),
        .rst(rst),
        .output_enable(sipo_output_enable),
        .eoc(gca_eoc),
        .push(psa_push),
        .ready(sipo_ready),
        .counter_val(counter_val),
        .output_enable_time(output_enable_time),
        .eoc_time(eoc_time),
        .push_time(push_time),
        .ready_time(ready_time)
    );

    always @(posedge clk) begin
        if (rst)
            data_out <= 0;
        else
            data_out <= gca_serial_data;
    end

endmodule