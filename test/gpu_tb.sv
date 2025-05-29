`timescale 1ns/1ps

module gpu_tb;
    // Parameters (match those in gpu.sv or override as needed)
    localparam DATA_MEM_ADDR_BITS = 8;
    localparam DATA_MEM_DATA_BITS = 8;
    localparam DATA_MEM_NUM_CHANNELS = 4;
    localparam PROGRAM_MEM_ADDR_BITS = 8;
    localparam PROGRAM_MEM_DATA_BITS = 16;
    localparam PROGRAM_MEM_NUM_CHANNELS = 1;
    localparam NUM_CORES = 2;
    localparam THREADS_PER_BLOCK = 4;

    // Clock and reset
    reg clk;
    reg reset;

    // Kernel Execution
    reg start;
    wire done;

    // Device Control Register
    reg device_control_write_enable;
    reg [7:0] device_control_data;

    // Program Memory
    wire [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_valid;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address [PROGRAM_MEM_NUM_CHANNELS-1:0];
    reg [PROGRAM_MEM_NUM_CHANNELS-1:0] program_mem_read_ready;
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data [PROGRAM_MEM_NUM_CHANNELS-1:0];

    // Data Memory
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_read_ready;
    reg [DATA_MEM_DATA_BITS-1:0] data_mem_read_data [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_valid;
    wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [DATA_MEM_NUM_CHANNELS-1:0];
    wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data [DATA_MEM_NUM_CHANNELS-1:0];
    reg [DATA_MEM_NUM_CHANNELS-1:0] data_mem_write_ready;

    // Flattened packed vectors for program and data memory
    wire [PROGRAM_MEM_NUM_CHANNELS*PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address_flat;
    reg [PROGRAM_MEM_NUM_CHANNELS*PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data_flat;
    wire [DATA_MEM_NUM_CHANNELS*DATA_MEM_ADDR_BITS-1:0] data_mem_read_address_flat;
    reg [DATA_MEM_NUM_CHANNELS*DATA_MEM_DATA_BITS-1:0] data_mem_read_data_flat;
    wire [DATA_MEM_NUM_CHANNELS*DATA_MEM_ADDR_BITS-1:0] data_mem_write_address_flat;
    wire [DATA_MEM_NUM_CHANNELS*DATA_MEM_DATA_BITS-1:0] data_mem_write_data_flat;

    // Assign packed vectors from arrays
    genvar ch;
    generate
        for (ch = 0; ch < PROGRAM_MEM_NUM_CHANNELS; ch = ch + 1) begin : pack_prog_addr
            assign program_mem_read_address_flat[(ch+1)*PROGRAM_MEM_ADDR_BITS-1:ch*PROGRAM_MEM_ADDR_BITS] = program_mem_read_address[ch];
            always @(*) program_mem_read_data[ch] = program_mem_read_data_flat[(ch+1)*PROGRAM_MEM_DATA_BITS-1:ch*PROGRAM_MEM_DATA_BITS];
        end
        for (ch = 0; ch < DATA_MEM_NUM_CHANNELS; ch = ch + 1) begin : pack_data_addr
            assign data_mem_read_address_flat[(ch+1)*DATA_MEM_ADDR_BITS-1:ch*DATA_MEM_ADDR_BITS] = data_mem_read_address[ch];
            always @(*) data_mem_read_data[ch] = data_mem_read_data_flat[(ch+1)*DATA_MEM_DATA_BITS-1:ch*DATA_MEM_DATA_BITS];
            assign data_mem_write_address_flat[(ch+1)*DATA_MEM_ADDR_BITS-1:ch*DATA_MEM_ADDR_BITS] = data_mem_write_address[ch];
            assign data_mem_write_data_flat[(ch+1)*DATA_MEM_DATA_BITS-1:ch*DATA_MEM_DATA_BITS] = data_mem_write_data[ch];
        end
    endgenerate

    // Instantiate the GPU
    gpu #(
        .DATA_MEM_ADDR_BITS(DATA_MEM_ADDR_BITS),
        .DATA_MEM_DATA_BITS(DATA_MEM_DATA_BITS),
        .DATA_MEM_NUM_CHANNELS(DATA_MEM_NUM_CHANNELS),
        .PROGRAM_MEM_ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS(PROGRAM_MEM_DATA_BITS),
        .PROGRAM_MEM_NUM_CHANNELS(PROGRAM_MEM_NUM_CHANNELS),
        .NUM_CORES(NUM_CORES),
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK)
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address_flat),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data(program_mem_read_data_flat),
        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address(data_mem_read_address_flat),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data(data_mem_read_data_flat),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address(data_mem_write_address_flat),
        .data_mem_write_data(data_mem_write_data_flat),
        .data_mem_write_ready(data_mem_write_ready)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    // Simple behavioral models for program and data memory
    reg [PROGRAM_MEM_DATA_BITS-1:0] program_mem [0:(1<<PROGRAM_MEM_ADDR_BITS)-1];
    reg [DATA_MEM_DATA_BITS-1:0] data_mem [0:(1<<DATA_MEM_ADDR_BITS)-1];

    integer i;
    // Program memory read model
    always @(*) begin
        for (i = 0; i < PROGRAM_MEM_NUM_CHANNELS; i = i + 1) begin
            program_mem_read_ready[i] = 1'b1;
            program_mem_read_data[i] = program_mem[program_mem_read_address[i]];
        end
    end

    // Data memory read/write model
    always @(*) begin
        for (i = 0; i < DATA_MEM_NUM_CHANNELS; i = i + 1) begin
            data_mem_read_ready[i] = 1'b1;
            data_mem_read_data[i] = data_mem[data_mem_read_address[i]];
            data_mem_write_ready[i] = 1'b1;
        end
    end

    // Data memory write
    always @(posedge clk) begin
        for (i = 0; i < DATA_MEM_NUM_CHANNELS; i = i + 1) begin
            if (data_mem_write_valid[i] && data_mem_write_ready[i])
                data_mem[data_mem_write_address[i]] <= data_mem_write_data[i];
        end
    end

    // Test sequence
    initial begin
        // Initialize memories
        for (i = 0; i < (1<<PROGRAM_MEM_ADDR_BITS); i = i + 1) program_mem[i] = 0;
        for (i = 0; i < (1<<DATA_MEM_ADDR_BITS); i = i + 1) data_mem[i] = 0;

        // Matrix Addition Kernel (matadd.asm) encoding:
        // Register mapping:
        // R0-R12: general purpose, R13: %blockIdx, R14: %blockDim, R15: %threadIdx
        //
        // MUL R0, %blockIdx, %blockDim      => 0x5_0_D_E
        // ADD R0, R0, %threadIdx            => 0x3_0_0_F
        // CONST R1, #0                      => 0x9_1_00
        // CONST R2, #8                      => 0x9_2_08
        // CONST R3, #16                     => 0x9_3_10
        // ADD R4, R1, R0                    => 0x3_4_1_0
        // LDR R4, R4                        => 0x7_4_4_0
        // ADD R5, R2, R0                    => 0x3_5_2_0
        // LDR R5, R5                        => 0x7_5_5_0
        // ADD R6, R4, R5                    => 0x3_6_4_5
        // ADD R7, R3, R0                    => 0x3_7_3_0
        // STR R7, R6                        => 0x8_7_7_6
        // RET                               => 0xF_0_0_0

        // Encoded instructions:
        program_mem[0]  = 16'h50DE; // MUL R0, %blockIdx, %blockDim
        program_mem[1]  = 16'h300F; // ADD R0, R0, %threadIdx
        program_mem[2]  = 16'h9100; // CONST R1, #0
        program_mem[3]  = 16'h9208; // CONST R2, #8
        program_mem[4]  = 16'h9310; // CONST R3, #16
        program_mem[5]  = 16'h3410; // ADD R4, R1, R0
        program_mem[6]  = 16'h7440; // LDR R4, R4
        program_mem[7]  = 16'h3520; // ADD R5, R2, R0
        program_mem[8]  = 16'h7550; // LDR R5, R5
        program_mem[9]  = 16'h3645; // ADD R6, R4, R5
        program_mem[10] = 16'h3730; // ADD R7, R3, R0
        program_mem[11] = 16'h8776; // STR R7, R6
        program_mem[12] = 16'hF000; // RET

        // Initialize data memory for matrix addition
        // matrix A: data_mem[0] to data_mem[7]
        data_mem[0] = 8'd0;
        data_mem[1] = 8'd1;
        data_mem[2] = 8'd2;
        data_mem[3] = 8'd3;
        data_mem[4] = 8'd4;
        data_mem[5] = 8'd5;
        data_mem[6] = 8'd6;
        data_mem[7] = 8'd7;
        // matrix B: data_mem[8] to data_mem[15]
        data_mem[8] = 8'd0;
        data_mem[9] = 8'd1;
        data_mem[10] = 8'd2;
        data_mem[11] = 8'd3;
        data_mem[12] = 8'd4;
        data_mem[13] = 8'd5;
        data_mem[14] = 8'd6;
        data_mem[15] = 8'd7;
        // matrix C: data_mem[16] to data_mem[23] (output)
        for (i = 16; i < 24; i = i + 1) data_mem[i] = 8'd0;

        // Reset sequence
        reset = 1;
        start = 0;
        device_control_write_enable = 0;
        device_control_data = 0;
        #20;
        reset = 0;

        // Set device control register (8 threads)
        device_control_data = 8'd8;
        device_control_write_enable = 1;
        #10;
        device_control_write_enable = 0;

        // Start kernel
        #10;
        start = 1;
        #10;
        start = 0;

        // Wait for done
        wait (done);
        #20;

        // Display result matrix C
        $display("Matrix C (data_mem[16] to data_mem[23]):");
        for (i = 16; i < 24; i = i + 1) $display("C[%0d] = %0d", i-16, data_mem[i]);
        $finish;
    end
endmodule 