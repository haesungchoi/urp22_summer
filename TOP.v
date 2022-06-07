////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////*
//
// 1. TOP module consists of 3 modules and 2 more small logics
//   1) FIFO
//   2) RAM
//   3) UART
//   4) clock diving logic
//   5) clock gating logic
//
// 2. CLOCK Frequency 
//   1) Main input CLK : 50MHZ
//   2) Divided clk inside of TOP module : 25MHz
//   3) 3 modules are operating based on the clock 25MHz 
//
// 3. Clock gating 
//   1) clock gating control signal : <check_result>
//   2) After dumping operation from ROM to RAM, there are some time interval
//   3) During the interval, user should input <check_result> to go to 
//      the Uart checking states 
//   
// 4. How this module operates
//   1) There are ROM and Uart module outside of this chip 
//      They are not in the synthesizable area, just for simulation

//   2) ROM Codes are coming into this module through Uart from outside

//   3) TOP module has FIFO, RAM, UART and those are in the synthesizable area

//   4) The received data are connected to the UART module directly 

//   5) FIFO module calls the Uart module inside the chip and transmit the
//      received data to RAM after translation from ASCII to binary format.
//      Because the uart data are based on ASCII format 

//   6) After finish of dumping, it remains the result checking states. 

//   7) It means that the stored data in RAM are written to the Uart module and 
//      check out the operation of Uart which shows some messages.


module TOP (
	CLK, 
	CLK_GATED,
	RESETn, 
	check_result, 

	stx, 
	srx

	);

/////////////////////////////////////
//         parameters              //
/////////////////////////////////////

parameter DATA_WIDTH = 8; // real width of ROM file  : equal to number of scan_cell  
parameter DATA_DEPTH = 64; // The number of lines of lst file  
parameter MEMORY_ADD_WIDTH = 8;

/////////////////////////////////////
//	  in, out ports            //
/////////////////////////////////////

input wire CLK;
output wire CLK_GATED;
input wire RESETn;
input wire check_result;

output wire stx;
input wire srx;

/////////////////////////////////////
//    internal wires : sram        //
/////////////////////////////////////

wire [MEMORY_ADD_WIDTH-1 : 0] sram_ADD_o; 	// 7:0
wire [DATA_WIDTH - 1 : 0] sram_DAT_i;  		// 7:0
wire [DATA_WIDTH - 1 : 0] sram_DAT_o;  		// 7:0
wire sram_CEN_o; 				// '0' is active  
wire sram_WEN_o; 				// '0' is active  

/////////////////////////////////////
//    internal wires : Uart        //
/////////////////////////////////////

wire [2:0] uart_addr_o;
wire [7:0] uart_wdata_o;
wire [7:0] uart_rdata_i;
wire uart_we_o;
wire uart_re_o;

wire   ctsn = 1'b0;
wire   dtr_pad_o;
wire   dsr_pad_i=1'b0;
wire   ri_pad_i =1'b0;
wire   dcd_pad_i=1'b0;
wire   rts_internal;

/////////////////////////////////////
//       clock gating              //
/////////////////////////////////////

wire clk_enable;


/////////////////////////////////////
//        instanciation            //
/////////////////////////////////////


RAM256X8 URAM256X8(
	.Q(sram_DAT_i),
	.CLK(~CLK_GATED), // give stable control signal value to memory
	.CEN(sram_CEN_o),
	.WEN(sram_WEN_o),
	.A(sram_ADD_o),
	.D(sram_DAT_o)
);
	
fifo	Ufifo(
	.CLK(CLK_GATED), 
	.RESETn(RESETn), 

	.sram_ADD_o(sram_ADD_o),
	.sram_DAT_i(sram_DAT_i),
	.sram_DAT_o(sram_DAT_o), 
	.sram_CEN_o(sram_CEN_o), // '0' is active   
	.sram_WEN_o(sram_WEN_o), // '0' is active  

	.uart_addr_o(uart_addr_o),
       	.uart_wdata_o(uart_wdata_o),       
	.uart_rdata_i(uart_rdata_i), 
	.uart_we_o(uart_we_o),
       	.uart_re_o(uart_re_o),

	.check_result(check_result), // user input to check result via uart
	.clk_enable(clk_enable)
);

uart_regs Uregs(
          .clk         (CLK_GATED),
          .wb_rst_i    (~RESETn),
          .wb_addr_i   (uart_addr_o),
          .wb_dat_i    (uart_wdata_o),
          .wb_dat_o    (uart_rdata_i),
          .wb_we_i     (uart_we_o),
          .wb_re_i     (uart_re_o),
          .modem_inputs({~ctsn, dsr_pad_i, ri_pad_i,  dcd_pad_i}),
          .stx_pad_o   (stx),
          .srx_pad_i   (srx),
          .rts_pad_o   (rts_internal),
          .dtr_pad_o   (dtr_pad_o),
          .int_o       ()
);

////////////////////////////////////////
// clock dividing from 50MHz to 25MHz //
////////////////////////////////////////
reg half_clk;
always @(negedge RESETn or posedge CLK ) 
begin
        if (RESETn==1'b0)   half_clk <= 1'b0;
        else               half_clk <= ~half_clk;
end

////////////////////////////////////////
// 	    CLOCK GATING	      //
////////////////////////////////////////
reg clk_en;
reg en_reg1;
reg en_reg2;
wire CLOCK_ENABLE;

// Below codes are to consider <clk_en> value.
// It is based on the value of <check_result> and <clk_enable>.
// <clk_enable> is from fifo and  value 1'b0 means that it likes to clock-down and wait the user input <check_result>
// <check_result> is the user input key value and 1'b1 means that the clock pulses are being restored 
// so <clk_en> value is 1'b1 after user key input
// 
always @(negedge RESETn or posedge CLK) 
begin
	if(RESETn == 1'b0) begin
		clk_en <= 1'b1;
	end
	else begin
		if(check_result) clk_en <= 1'b1;
		else clk_en <= clk_enable;
	end	
end

// registering 2 times 
// it prevents glitches on <clk_en> and make stable signal which is named <CLOCK_ENABLE>

always @(negedge RESETn or negedge CLK)
begin
	if(RESETn == 1'b0) begin
		en_reg1 <= 1'b0;
		en_reg2 <= 1'b0;
	end
	else begin
		en_reg1 <= clk_en;
		en_reg2 <= en_reg1;
	end

end

assign CLOCK_ENABLE = en_reg2 && en_reg1;

// turn on and off below codes alternatively 

//assign CLK_GATED = half_clk & CLOCK_ENABLE;

ClockGate UClockGate(
        .en(CLOCK_ENABLE),
        .CLK(half_clk),
        .gCLK(CLK_GATED)
);

endmodule



module ClockGate(
        input   wire    en,
        input   wire    CLK,
        output  wire    gCLK
);

        // synopsys dc_script_begin
        // set_dont_touch cg
        // synopsys dc_script_end
        TLATNCAX8       cg(
        	.E(en),  
        	.CK(CLK),
        	.ECK(gCLK)
	);
endmodule
