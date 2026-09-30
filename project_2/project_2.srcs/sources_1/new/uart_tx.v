module uart_tx(
input clk,
input rst,
input send_go,
input [7:0]data,
output reg uart_tx,
output reg tx
);

parameter BAUD=9600;
parameter CLOCK_FREQ=25000000;
parameter MCNT_BAUD=CLOCK_FREQ/BAUD-1;

reg [7:0]r_data;
reg [29:0]cnt1;
reg cnt3;
reg [3:0]cnt2;
wire w_tx;

always@(posedge clk)begin
   if(!rst)
      r_data<=0;
   else if(send_go)
      r_data<=data;
   else
      r_data<=r_data;
end

always@(posedge clk)begin
   if(!rst)
      cnt1<=0;
   else if(cnt3)
      if(cnt1==MCNT_BAUD)
         cnt1<=0;
      else
         cnt1<=cnt1+1'd1;
   else
      cnt1<=0;
end

always@(posedge clk)begin
   if(!rst)
      cnt2<=0;
   else if(cnt1==MCNT_BAUD)
      if(cnt2==9)
         cnt2<=0;
      else
         cnt2<=cnt2+1'd1;
end

always@(posedge clk)begin
   if(!rst)
      uart_tx<=1'd1;
   else if(cnt3==0)
      uart_tx<=1'd1;
   else
      case(cnt2)
         0:uart_tx<=1'd0;
         1:uart_tx<=r_data[0];
         2:uart_tx<=r_data[1];
         3:uart_tx<=r_data[2];
         4:uart_tx<=r_data[3];
         5:uart_tx<=r_data[4];
         6:uart_tx<=r_data[5];
         7:uart_tx<=r_data[6];
         8:uart_tx<=r_data[7];
         9:uart_tx<=1'd1;
         default:uart_tx<=uart_tx;
      endcase
end

always@(posedge clk)begin
   if(!rst)
      cnt3<=0;
   else if(send_go)
      cnt3<=1;
   else if(w_tx)
      cnt3<=0;
end

assign w_tx=((cnt2==9)&&(cnt1==MCNT_BAUD));

always@(posedge clk)
   tx<= w_tx;

endmodule
