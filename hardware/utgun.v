module utgun(
    input clk_i,
    input rst_i,
    input [31:0] inst_i,
    input [31:0] data_mem_rdata_i,
    output reg [31:0] pc_o,
    output [1023:0] regs_o,
    output reg data_mem_we_o,
    output reg [31:0] data_mem_addr_o,
    output reg [31:0] data_mem_wdata_o,
    output reg [1:0] cur_stage_o
);

// Register file
reg [31:0] regs [0:31];

// State definitions
localparam FETCH = 2'd0, DECODE = 2'd1, EXECUTE = 2'd2, WRITEBACK = 2'd3;

// Decoded instruction fields
reg [31:0] instruction; // Little-endian converted
reg [6:0] opcode;
reg [4:0] rd, rs1, rs2;
reg [2:0] funct3;
reg [6:0] funct7;
reg [10:0] funct11;
reg s1_bit;
reg [1:0] s2_bits;
// ... immediate values
reg [31:0] imm_i; 
reg [31:0] imm_s; 
reg [31:0] imm_b;
reg [31:0] imm_u; 
reg [31:0] imm_j; 
reg [31:0] imm_c; 

// Add these to hold temporary data:
reg [31:0] loaded_val1;
reg [31:0] product_temp;  // To hold the product result in MAC operation
// Execute stage counter for multi-cycle instructions
reg [31:0] exec_cycle_count;

// Endianness conversion
wire [31:0] inst_converted = {inst_i[7:0], inst_i[15:8], inst_i[23:16], inst_i[31:24]};

reg [31:0] next_pc;
reg [31:0] alu_result;

reg write_rd;

integer a;

always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin 
        pc_o <= 32'b0;
        cur_stage_o <= FETCH;
        exec_cycle_count <= 0;
        write_rd <= 0;
        data_mem_we_o <= 0;
        data_mem_addr_o <= 0;
        data_mem_wdata_o <= 0;
        instruction <= 32'b0; 
        for (a = 0; a < 32; a = a + 1) begin
            regs[a] <= 32'b0;
        end
        
    end else begin
        case (cur_stage_o)
            FETCH: begin
                instruction <= inst_converted;
                cur_stage_o <= DECODE;
            end
            DECODE: begin
                opcode <= instruction[6:0];
                rd     <= instruction[11:7];
                funct3 <= instruction[14:12];
                rs1    <= instruction[19:15];
                rs2    <= instruction[24:20];
                funct7 <= instruction[31:25];
                 
                // For Custom instruction 1
                funct11 <= instruction[30:20];
                // Custom instruction extra bits:
                s1_bit <= instruction[31];      // For SEL.PART
                s2_bits <= instruction[31:30];  // For SEL.CND and MAC.LD.ST
    
                // I-type immediate (12-bit, sign-extended)
                imm_i <= {{20{instruction[31]}}, instruction[31:20]};
                
                // S-type immediate (12-bit, sign-extended)
                imm_s <= {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
                
                // B-type immediate (13-bit, sign-extended, LSB=0)
                imm_b <= {{19{instruction[31]}}, instruction[31], instruction[7], 
                          instruction[30:25], instruction[11:8], 1'b0};
                
                // U-type immediate (upper 20 bits)
                imm_u <= {instruction[31:12], 12'b0};
                
                // J-type immediate (21-bit, sign-extended, LSB=0)
                imm_j <= {{11{instruction[31]}}, instruction[31], instruction[19:12], 
                          instruction[20], instruction[30:21], 1'b0};
                // Custom-type2 immediate (11-bit, sign-extended, LSB=0)
                imm_c <= {{21{instruction[7]}}, instruction[7], instruction[29:25], instruction[11:8], 1'b0};
                // Breakdown: sign_ext(21) | imm[10](1) | imm[9:5](5) | imm[4:1](4) | imm[0]=0
                
                cur_stage_o <= EXECUTE;
            end
            EXECUTE: begin
                
                case (opcode) 
                    //LUI
                    7'b0110111: begin 
                        alu_result <= imm_u;
                        next_pc <= pc_o + 4 ;
                        write_rd <= 1;
                        cur_stage_o <= WRITEBACK;   
                        
                    end
                    //AUIPC
                    7'b0010111: begin
                        alu_result <= pc_o + imm_u;
                        next_pc <= pc_o + 4 ;
                        write_rd <= 1;
                        cur_stage_o <= WRITEBACK;
                    end
                    //JAL
                    7'b1101111: begin 
                        alu_result <= pc_o + 4;
                        next_pc <= pc_o + imm_j;
                        write_rd <= 1;
                        cur_stage_o <= WRITEBACK;
                        
                    end
                    //JALR
                    7'b1100111: begin 
                        alu_result <= pc_o + 4;
                        next_pc <= (regs[rs1] + imm_i) & 32'hFFFFFFFE;
                        write_rd <= 1;  
                        cur_stage_o <= WRITEBACK;
                        
                    end
                    //LW
                    7'b0000011: begin 
                        data_mem_addr_o <= regs[rs1] + imm_i;
                        next_pc <= pc_o + 4;
                        write_rd <= 1;  
                        cur_stage_o <= WRITEBACK;
                        
                    end
                    //SW
                    7'b0100011: begin 
                        data_mem_addr_o <= regs[rs1] + imm_s;
                        data_mem_wdata_o <= regs[rs2];
                        data_mem_we_o <= 1'b1;
                        next_pc <= pc_o + 4;
                        write_rd <= 0;
                        cur_stage_o <= WRITEBACK;
                    end
                    
                    7'b1100011: begin 
                    
                        case (funct3) 
                            //BEQ
                            3'b000: begin 
                                if ($signed(regs[rs1]) == $signed(regs[rs2])) begin 
                                    next_pc <= pc_o + imm_b;
                                end else begin 
                                    next_pc <= pc_o + 4;
                                end
                                write_rd <= 0;
                                cur_stage_o <= WRITEBACK;
                            end
                            //BGE
                            3'b101: begin 
                               if ($signed(regs[rs1]) >= $signed(regs[rs2])) begin 
                                    next_pc <= pc_o + imm_b;
                                end else begin 
                                    next_pc <= pc_o + 4;
                                end
                                write_rd <= 0;
                                cur_stage_o <= WRITEBACK;
                            end
                        endcase
                    end
                    
                    7'b0010011: begin 
                    
                        case (funct3) 
                            //ADDI
                            3'b000: begin 
                                alu_result <= $signed(regs[rs1]) + imm_i;
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                                
                            end
                            //SLTIU
                            3'b011 : begin 
                                if ($unsigned(regs[rs1]) < $unsigned(imm_i)) begin 
                                    alu_result <= 1;
                                end else begin 
                                    alu_result <= 0;
                                end
                                write_rd <= 1;
                                next_pc <= pc_o + 4;
                                cur_stage_o <= WRITEBACK;
                            end                         
                            //XORI
                            3'b100: begin 
                                alu_result <= regs[rs1] ^ imm_i;
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                                
                            end
                            //SLLI
                            3'b001: begin 
                                alu_result <= regs[rs1] << imm_i[4:0];
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                                
                            end
                        endcase
                    end
                    // R-TYPE Instructions
                    // Opcode: 0110011
                    7'b0110011: begin 
                        case (funct3) 
                            // ADD / SUB                     
                            3'b000: begin 
                                if (funct7[5]) begin // SUB
                                    alu_result <= $signed(regs[rs1]) - $signed(regs[rs2]);
                                end else begin       // ADD
                                    alu_result <= $signed(regs[rs1]) + $signed(regs[rs2]);
                                end
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // SLT 
                            3'b010: begin 
                                if ($signed(regs[rs1]) < $signed(regs[rs2])) begin
                                    alu_result <= 32'd1;
                                end else begin
                                    alu_result <= 32'd0;
                                end
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // SLTU 
                            3'b011: begin 
                                if ($unsigned(regs[rs1]) < $unsigned(regs[rs2])) begin 
                                    alu_result <= 32'd1;
                                end else begin
                                    alu_result <= 32'd0;
                                end
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // SRA 
                            // funct7 is given as 0100000 in the table (SRA)
                            3'b101: begin  // SRA
                                alu_result <= $signed(regs[rs1]) >>> regs[rs2][4:0];
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // AND (funct3: 111)
                            3'b111: begin 
                                alu_result <= regs[rs1] & regs[rs2];
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end
                            
                        endcase
                    end
                    
                    7'b1110111: begin
                        case (funct3)
                            // SUB.ABS: |rs1 - rs2|
                            3'b000: begin
                                if ($signed(regs[rs1]) > $signed(regs[rs2])) begin
                                    alu_result <= $signed(regs[rs1]) - $signed(regs[rs2]);
                                end else begin
                                    alu_result <= $signed(regs[rs2]) - $signed(regs[rs1]); // Flip if negative
                                end
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // SEL.PART: 
                            3'b010: begin
                                if (s1_bit == 1'b1) begin
                                    // Most significant 16-bit (Upper 16 bits), unsigned extended
                                    alu_result <= {16'b0, regs[rs1][31:16]};
                                end else begin
                                    // Least significant 16-bit (Lower 16 bits)
                                    alu_result <= {16'b0, regs[rs1][15:0]};
                                end
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // AVG.FLR
                            3'b100: begin
                                // Adding with $signed and shifting right by 1 bit (arithmetic shift) is dividing by 2 and taking the floor.
                                alu_result <= ($signed(regs[rs1]) + $signed(imm_i)) >>> 1;
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end

                            // MOVU
                            
                            3'b101: begin                             
                                // Document says "unsigned extended". Since imm_i was sign-extended during the decode stage
                                alu_result <= {20'b0, instruction[31:20]};
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end 

                            // SRCH.BIT.PTRN       
                            3'b111: begin 
                                alu_result <= 0; 
                                
                                for (a = 0; a <= 24; a = a + 1) begin
                                     if (regs[rs1][a +: 8] == regs[rs2][7:0]) begin
                                         alu_result <= 1;
                                     end
                                end
                                
                                next_pc <= pc_o + 4;
                                write_rd <= 1;
                                cur_stage_o <= WRITEBACK;
                            end
                        
                            // SRT.CMP.ST
                            3'b001: begin
                                if (exec_cycle_count == 0) begin
                                    // Cycle 1: Compare and prepare to write the smaller one
                                    // Address: regs[rd]
                                    data_mem_addr_o <= regs[rd];
                                    data_mem_we_o <= 1'b1;
                                    
                                    if ($signed(regs[rs1]) < $signed(regs[rs2]))
                                        data_mem_wdata_o <= regs[rs1]; // Smaller is rs1
                                    else
                                        data_mem_wdata_o <= regs[rs2]; // Smaller is rs2
                                        
                                    exec_cycle_count <= exec_cycle_count + 1;
                                    // Not changing stage! We are still in EXECUTE.
                                end 
                                else if (exec_cycle_count == 1) begin
                                    // Cycle 2: Prepare to write the larger one
                                    // Address: regs[rd] + 4
                                    data_mem_addr_o <= regs[rd] + 32'd4;
                                    data_mem_we_o <= 1'b1;
                                    
                                    if ($signed(regs[rs1]) < $signed(regs[rs2]))
                                        data_mem_wdata_o <= regs[rs2]; // Larger is rs2
                                    else
                                        data_mem_wdata_o <= regs[rs1]; // Larger is rs1
                                        
                                    // Operation finished
                                    next_pc <= pc_o + 4;
                                    write_rd <= 0; // Not writing to register, writing to memory.
                                    cur_stage_o <= WRITEBACK;
                                    exec_cycle_count <= 0; // Reset the counter
                                end
                            end
                            
                            // LD.CMP.MAX - Exactly 3 Cycles
                            // Cycle 0: Send the 1st address (regs[rd]).
                            // Cycle 1: Read the 1st data, send the 2nd address (regs[rs1]).
                            // Cycle 2: Read the 2nd data, send the 3rd address (regs[rs2]), compare the first two.
                            // Cycle 3 (WRITEBACK): Read the 3rd data and perform final comparison.                            
                            3'b110: begin
                                if (exec_cycle_count == 0) begin
                                    // --- CYCLE 0 ---
                                    // First address (value inside rd)
                                    data_mem_addr_o <= regs[rd];
                                    data_mem_we_o <= 1'b0; // Read mode
                                    
                                    exec_cycle_count <= 1;
                                end 
                                else if (exec_cycle_count == 1) begin
                                    // --- CYCLE 1 ---
                                    // Data requested in Cycle 0 is now ready in data_mem_rdata_i.
                                    loaded_val1 <= data_mem_rdata_i;
                                    
                                    // Second address (rs1)
                                    data_mem_addr_o <= regs[rs1];
                                    
                                    exec_cycle_count <= 2;
                                end 
                                else if (exec_cycle_count == 2) begin
                                    // --- CYCLE 2 ---
                                    // Data requested in Cycle 1 is ready.
                                    
                                    // Third and final address (rs2)
                                    data_mem_addr_o <= regs[rs2];
                                    
                                    // Let's compare the first two numbers now and assign the result to alu_result.
                                    // This way, our job in Writeback becomes easier.
                                    
                                    if ($signed(loaded_val1) >= $signed(data_mem_rdata_i)) 
                                        alu_result <= loaded_val1;
                                    else 
                                        alu_result <= data_mem_rdata_i; // Currently max(val1, val2) is stored here
                                        
                                    // Execute finished, next cycle will be WRITEBACK
                                    next_pc <= pc_o + 4;
                                    write_rd <= 1; 
                                    cur_stage_o <= WRITEBACK;
                                    exec_cycle_count <= 0;
                                end
                            end
                        endcase
                    end
                    // CUSTOM INSTRUCTIONS GROUP 2            
                    7'b1111111: begin
                        case (funct3)
                            
                            // SEL.CND 
                            // Opcode: 1111111, Funct3: 000
                            // s2_bits: Instruction[31:30] (Captured during decode stage)
                            3'b000: begin
                                case (s2_bits)
                                    // s2 = 00: Branch if equal (==)
                                    2'b00: begin 
                                        if ($signed(regs[rs1]) == $signed(regs[rs2])) 
                                            next_pc <= pc_o + imm_c; // imm_c should be sign-extended and LSB=0
                                        else 
                                            next_pc <= pc_o + 4;
                                    end
                                    
                                    // s2 = 01: Branch if greater or equal (>=)
                                    2'b01: begin 
                                        if ($signed(regs[rs1]) >= $signed(regs[rs2]))
                                             next_pc <= pc_o + imm_c;
                                        else
                                             next_pc <= pc_o + 4;
                                    end
                                    
                                    // s2 = 10: Branch if less than (<)
                                    2'b10: begin 
                                        if ($signed(regs[rs1]) < $signed(regs[rs2]))
                                             next_pc <= pc_o + imm_c;
                                        else
                                             next_pc <= pc_o + 4;
                                    end
                                    
                                    // s2 = 11: NOP (No operation, just increment PC)
                                    2'b11: begin 
                                        next_pc <= pc_o + 4;
                                    end
                                endcase
                                
                                write_rd <= 0; // This is a branch operation, not written to register.
                                cur_stage_o <= WRITEBACK;
                            end

                            // MAC.LD.ST - Multi-cycle (Variable cycles)
                            // Opcode: 1111111, Funct3: 111
                            3'b111: begin
                                // Last 2 bits of exec_cycle_count (modulo 4) show which step we are in: 0,1,2,3
                                case (exec_cycle_count[1:0]) 
                                    
                                    // STEP 1: Read from rs1
                                    2'b00: begin
                                        // Address: regs[rs1] + (Iteration Count * 4)
                                        // (exec_cycle_count >> 2) gives us the iteration count.
                                        data_mem_addr_o <= regs[rs1] + ((exec_cycle_count >> 2) * 32'd4);
                                        data_mem_we_o <= 1'b0; // Read
                                        
                                        // Move to next cycle
                                        exec_cycle_count <= exec_cycle_count + 1;
                                    end
                            
                                    // STEP 2: Read from rs2 (and store rs1 data)
                                    2'b01: begin
                                        loaded_val1 <= data_mem_rdata_i; // Grab the rs1 data coming from STEP 1
                                        
                                        // Now give the rs2 address: regs[rs2] + (Iteration Count * 4)
                                        data_mem_addr_o <= regs[rs2] + ((exec_cycle_count >> 2) * 32'd4);
                                        data_mem_we_o <= 1'b0; // Read
                                        
                                        exec_cycle_count <= exec_cycle_count + 1;
                                    end
                            
                                    // STEP 3: Multiply, store result and read Accumulator
                                    2'b10: begin
                                        // Perform multiplication: loaded_val1 (rs1) * data_mem_rdata_i (rs2)
                                        // Assign the result to product_temp.
                                        product_temp <= $signed(loaded_val1) * $signed(data_mem_rdata_i);
                            
                                        // Now give the address to read the old value (Accumulator) to perform addition.
                                        // Address: Immediate value (Fixed address)
                                        data_mem_addr_o <= imm_c; 
                                        data_mem_we_o <= 1'b0; // Read
                                        
                                        exec_cycle_count <= exec_cycle_count + 1;
                                    end
                            
                                    // STEP 4: Add and write back (Store)
                                    2'b11: begin
                                        // Addition: Mem[imm] (just arrived) + Product (calculated in previous step)
                                        data_mem_wdata_o <= product_temp + data_mem_rdata_i;
                                        
                                        // Write command
                                        data_mem_addr_o <= imm_c; // Same address again
                                        data_mem_we_o <= 1'b1;    // WRITE!
                            
                                        // LOOP CONTROL
                                        // If (Current Iteration Count) == s2_bits then finish.
                                        if ((exec_cycle_count >> 2) == s2_bits) begin
                                            next_pc <= pc_o + 4;
                                            write_rd <= 0; // Written to memory not to register.
                                            cur_stage_o <= WRITEBACK;
                                            exec_cycle_count <= 0; // Reset the counter
                                        } else begin
                                            // Otherwise continue as cycle count increases [1:0] will become 00 again
                                            exec_cycle_count <= exec_cycle_count + 1;
                                        end
                                    end
                                endcase
                            end
                        endcase
                    end
                endcase
            end
            WRITEBACK: begin
                if (write_rd && rd != 5'b0) begin
                    
                    // Case 1: Standard LW (Load Word)
                    if (opcode == 7'b0000011) begin
                        regs[rd] <= data_mem_rdata_i;
                    end 
                    
                    // Case 2: LD.CMP.MAX (Custom Load)
                    // Opcode: 1110111 and Funct3: 110
                    else if (opcode == 7'b1110111 && funct3 == 3'b110) begin
                        // We have the following:
                        // alu_result       -> max(val1, val2) (Came from Execute stage)
                        // data_mem_rdata_i -> val3 (Fresh data currently coming from memory)
                        
                        // Final Comparison:
                        if ($signed(alu_result) >= $signed(data_mem_rdata_i))
                            regs[rd] <= alu_result;       // Old winner is larger
                        else
                            regs[rd] <= data_mem_rdata_i; // New arrival is larger
                    end
                    
                    // Case 3: All other ALU operations (ADD, SUB, etc.)
                    else begin
                        regs[rd] <= alu_result;
                    end
                end
                
                data_mem_we_o <= 1'b0;
                pc_o <= next_pc;
                cur_stage_o <= FETCH;
            end
        endcase
    end
end

// Connect register file to output
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : reg_assign
        assign regs_o[i*32 +: 32] = regs[i];
    end
endgenerate

endmodule
