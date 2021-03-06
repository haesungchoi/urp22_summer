module FC_MEMORY #(
parameter FRT_CELL = 32,
parameter MID_CELL = 20,
parameter BCK_CELL = 10,
parameter BATCH_SIZE = 32)(
input clk,
input reset_n,

input we,               //data write enable
input [15:0] data,
input [15:0] addr,

input fc1_com_end,      //FC1 computation finish
input fc2_com_end,      //FC2 computation finish
input bck_prop_start,   //start back propagation in each batch 
input batch_end,        //all 32 mini batch is done update weight

output [15:0] re_data,
output reg fc_bck_prop_end,     //FC back propagation end(single mini batch)

//deleted by sm
//output reg [15:0] fc_err_prop,  //FC back propagation data
//output reg [15:0] fc_err_addr,  //FC back propagation address
output reg fc_batch_end         //update weight done at the time all 32 mini batch done
);

`include "fixed_mult.v"
// `include "bits_required.v"

parameter LN_RATIO = (16'b1 << 5);    //0000_0000_0010_0000==32
parameter NBITS = 12;
//bits_required((2*FRT_CELL*MID_CELL) + (2*FRT_CELL),1'b0);

//added by sm
//parameter sm = bits_required(BATCH_SIZE-1,1'b0);
//added by sm

// Declare the RAM variable
//reg signed [15:0] ram[2:0][0:((2*FRT_CELL*MID_CELL) + (2*FRT_CELL) - 1)];
reg [1:0] mem_num_d, mem_num_m;

// Variable to hold the registered read address
reg [NBITS-1:0] addr_reg;

reg signed [15:0] i, j, k, back_i, mid_i, mid_j, front_i, front_j, out_i;
reg signed [15:0] update_i, update_j;

// Modified by JH
reg signed [15:0] ram0[0:((2*FRT_CELL*MID_CELL) + (2*FRT_CELL) - 1)];
reg signed [15:0] ram1[0:((2*BCK_CELL*MID_CELL) + (2*BCK_CELL) - 1)];
reg signed [15:0] ram2[0:29];
reg [15:0] re_data_reg;




always @ (posedge clk or negedge reset_n)
begin
    //initialize
    if (!reset_n) begin

        /*-----------------------------ram0---------------------------------
        0~31(0~FRT_CELL-1) : convolution result
        32~671(~FRT_CELL + FRT_CELL*MID_CELL - 1) : first weight, updated batch done
        672~703(~2*FRT_CELL + FRT_CELL*MID_CELL - 1) : error to propagate
        8704~1343(~2*FRT_CELL + 2*FRT_CELL*MID_CELL - 1) : accumulate delta weight
        ------------------------------------------------------------------*/
        /*for (i=0; i<(FRT_CELL * MID_CELL); i = i+1) begin
            ram[0][2*FRT_CELL + FRT_CELL*MID_CELL + i] <= 1'b0;
        end*/

        for (i=0; i<(FRT_CELL * MID_CELL); i = i+1) begin
            ram0[2*FRT_CELL + FRT_CELL*MID_CELL + i] <= 1'b0;
        end

        for (j=0; j<(FRT_CELL * MID_CELL); j = j+1) begin
            ram1[2*FRT_CELL + FRT_CELL*MID_CELL + j] <= 1'b0;
        end
        
        for (i=0; i<30; i = i+1) begin
            ram2[i] <= 1'b0;
        end


       
        /*-----------------------------ram1--------------------------------
        0~19(0~MID_CELL-1) : forward propagation cell result
        20~219(~MID_CELL + MID_CELL*BCK_CELL- 1) : second weight, updated batch done
        220~239(~2*MID_CELL + MID_CELL*BCK_CELL - 1) : error to propagate
        240~439(~2*MID_CELL + 2*MID_CELL*BCK_CELL - 1) : accumulate delta weight
        ------------------------------------------------------------------*/
        /*for (j=0; j<(MID_CELL * BCK_CELL); j = j+1) begin
            ram[1][2*MID_CELL + MID_CELL*BCK_CELL + j] <= 1'b0;
        end*/ 

        back_i <= 1'b0;
        mid_i <= 1'b0;
        mid_j <= 1'b0;
        front_i <= 1'b0; 
        front_j <= 1'b0;
        out_i <= 1'b0;
        update_i <= 1'b0;
        update_j <= 1'b0;

        
        /*-----------------------------ram2--------------------------------
        0~9(0~BCK_CELL-1): forward propagation cell result
        10~19(BCK_CELL~2*BCK_CELL-1) : right answer
        20~29(2*BCK_CELL~3*BCK_CELL-1) : error
        ----------------------------------------------------------------*/
    end else begin
        
        
        
        
        //-------------------------back propagation start------------------------------------------------------------------------------//
        if (bck_prop_start) begin
            if (back_i >= 0) begin
                if (back_i < BCK_CELL) begin
                    ram2[back_i + 20] <= ram2[BCK_CELL + back_i] - ram2[back_i] ;
                    back_i <= back_i + 1'b1;
                    
                    
                end else begin  //first error, weight update
                    if (mid_i < BCK_CELL) begin
                        if (mid_j < MID_CELL) begin
                            if (mid_i == 1'b0) begin    //initialize
                                ram1[MID_CELL*BCK_CELL + MID_CELL + mid_j] 
                                    <= fixed_mult(ram1[MID_CELL + mid_j], ram2[20 + mid_i]);
                            end else begin
                            //error' = error + error# * weight
                            ram1[MID_CELL*BCK_CELL + MID_CELL + mid_j]
                                <= ram1[MID_CELL*BCK_CELL + MID_CELL + mid_j]
                                + fixed_mult(ram1[MID_CELL + mid_i*MID_CELL + mid_j], ram2[2*BCK_CELL + mid_i]);     //error
                            end
                            
                            //delta weight = r * cell * error
                            ram1[2*MID_CELL + MID_CELL*BCK_CELL + mid_i*MID_CELL + mid_j]
                                <= ram1[2*MID_CELL + MID_CELL*BCK_CELL + mid_i*MID_CELL + mid_j]
                                    + fixed_mult(ram2[2*BCK_CELL + mid_i], fixed_mult(ram1[mid_j], LN_RATIO));       //delta weight
                            mid_j <= mid_j + 1'b1;
                            if (mid_j == (MID_CELL - 1'b1)) begin
                                mid_i <= mid_i + 1'b1;
                                mid_j <= 1'b0;
                            end
                        end
                    end else begin  //second error, weight update
                        if (front_i < MID_CELL) begin
                            if (front_j < FRT_CELL) begin
                                if (front_i == 1'b0) begin    //initialize
                                    ram0[FRT_CELL*MID_CELL + FRT_CELL + front_j] 
                                        <= fixed_mult(ram0[FRT_CELL + front_j], ram1[MID_CELL*BCK_CELL + MID_CELL + front_i]);
                                end else begin
                                //error' = error + error# * weight
                                ram0[FRT_CELL*MID_CELL + FRT_CELL + front_j]
                                    <= ram0[FRT_CELL*MID_CELL + FRT_CELL + front_j]
                                    + fixed_mult(ram0[FRT_CELL + front_i*FRT_CELL + front_j], ram1[MID_CELL*BCK_CELL + MID_CELL + front_i]);     //error
                                end
                                
                                //delta weight = r * cell * error
                                ram0[2*FRT_CELL + FRT_CELL*MID_CELL + front_i*FRT_CELL + front_j]
                                    <= ram0[2*FRT_CELL + FRT_CELL*MID_CELL + front_i*FRT_CELL + front_j]
                                        + fixed_mult(ram1[MID_CELL*BCK_CELL + MID_CELL + front_i], fixed_mult(LN_RATIO, ram0[front_j]));       //delta weight
                                front_j <= front_j + 1'b1;
                                if (front_j == (FRT_CELL - 1'b1)) begin
                                    front_i <= front_i + 1'b1;
                                    front_j <= 1'b0;
                                end
                            end
                            
                        //propagate output error
                        end else if (out_i < FRT_CELL) begin
                            //deleted by sm
                            //fc_err_prop <= ram[0][FRT_CELL*MID_CELL + FRT_CELL + out_i];
                            //fc_err_addr <= out_i;
                            out_i <= out_i + 1'b1;
                        end else begin
                            fc_bck_prop_end <= 1'b1;
                        end
                    end
                end
            end else begin
                {back_i, mid_i, mid_j, front_i, front_j, out_i} <= 1'b0;
            end
        end else begin
            if (we) begin
                case (mem_num_d) // DEMUX modified by JH
                    2'd0 : ram0[addr] <= data;
                    2'd1 : ram1[addr] <= data;
                    2'd2 : ram2[addr] <= data;
                endcase//ram[mem_num_d][addr] <= data;
            end
            addr_reg <= addr;
            
            {back_i, mid_i, mid_j, front_i, front_j, out_i} <= 1'sb1;
            fc_bck_prop_end <= 1'b0;
        end
        
        //---------------------------------32 mini batch finished-----------------------------------//
        if (batch_end) begin
            if (update_i < (FRT_CELL*MID_CELL)) begin
              //bits_required(blahblah) is changedto sm  by sm 
                ram0[FRT_CELL + update_i] <= ram0[FRT_CELL + update_i] + (ram0[2*FRT_CELL + FRT_CELL*MID_CELL + update_i] >>> 3'd5);
                ram0[2*FRT_CELL + FRT_CELL*MID_CELL + update_i] <= 1'b0;
                update_i <= update_i + 1'b1;
            end else begin
                fc_batch_end <= 1'b1;
            end
            if (update_j < (MID_CELL*BCK_CELL)) begin
                ram1[MID_CELL + update_j] <= ram1[MID_CELL + update_j] + (ram1[2*MID_CELL + MID_CELL*BCK_CELL + update_j] >>> 3'd5 );
                ram1[2*MID_CELL + MID_CELL*BCK_CELL + update_j] <= 1'b0;
                update_j <= update_j + 1'b1;
            end
        end else begin
            {update_i, update_j,fc_batch_end} <= 1'b0;
        end
    end
end

//demux, connect input 'we', 'data', 'addr' to ram
always @(*)
begin : DEMUX
    case ({fc1_com_end,fc2_com_end})
        2'b00 : mem_num_d = 2'd0;
        2'b01 : mem_num_d = 2'd0;
        2'b10 : mem_num_d = 2'd1;
        2'b11 : mem_num_d = 2'd2;
        //default mem_num_d = 1'b0; (deleted by HS)
    endcase
end

//mux, connect output data 're_data'
always @(*)
begin : MUX
    case ({fc1_com_end,fc2_com_end})
        2'b00 : mem_num_m = 2'd0;
        2'b01 : mem_num_m = 2'd0;
        2'b10 : mem_num_m = 2'd1;
        2'b11 : mem_num_m = 2'd2;
        //default mem_num_m = 1'b0; (deleted by HS)
    endcase
end

always @(*)
begin : DATA_DEMUX
    case (mem_num_m)
        2'd0 : re_data_reg = ram0[addr_reg]; 
        2'd1 : re_data_reg = ram1[addr_reg];
        2'd2 : re_data_reg = ram2[addr_reg];
    endcase
end

assign re_data = re_data_reg;
//assign re_data = ram[mem_num_m][addr_reg];

//assign re_data = 2'b1;
//assign re_data = 2'b0;

endmodule
