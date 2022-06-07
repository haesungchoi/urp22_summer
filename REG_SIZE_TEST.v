module REG_SIZE_TEST#(

parameter FRT_CELL = 32,
parameter MID_CELL = 20,
parameter BCK_CELL = 10)



(
    input [15:0]a,
    input clk,
    output [15:0]b
    );
   reg signed [15:0] i;

    reg [15:0] c[2:0][0:((2*FRT_CELL*MID_CELL) + (2*FRT_CELL) - 1)];


   
    always@(posedge clk)begin   



    for (i=0; i<(FRT_CELL * MID_CELL); i = i+1) begin
            c[0][2*FRT_CELL + FRT_CELL*MID_CELL + i] <= 1'b0;
        end

    end

    assign b =  c[1][1000];
 

endmodule
  
