function integer bits_required (
    input integer val,
    input integer required
);
 
//integer remainder;
//reg  required;

   // remainder = val;
   // required = 1'b0;
    
    // Iteration for each bit
    while ( val > 1'b0) begin
        required = required + 1'b1;
        val = val >> 1;
    end
    bits_required = required;

endfunction
