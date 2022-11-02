module cynlr_camera;

    reg dcm_clk, master_adc, slave_adc;
  	reg ready, system_rst;
  	wire slave_bus, master_bus;
  	reg slave_write, master_write;
  	wire slave_rst_cam, master_rst_cam, slave_sample_cam, master_sample_cam, reset;
    localparam period = 10;
  	localparam delay_interconnect = 100; //100/50 = 2
  
  	wire [7:0] mismatch_delay;
  	
    pullup(slave_bus);
  	pullup(master_bus);
  
  master_module UUT1 (
    .rst_FSM(system_rst),
    .pix_clk(dcm_clk), 
    .end_adc(master_adc), 
    .mismatch_delay(mismatch_delay),
    .ready(ready),
    .control_slave(slave_bus), 
    .rst_cam(master_rst_cam), 
    .sample_cam(master_sample_cam),
    .rst_cu(reset));
  
  slave_module UUT2 (
    .rst_FSM(system_rst),
    .pix_clk(dcm_clk), 
    .end_adc(slave_adc), 
    .feedback_master(master_bus), 
    .rst_cam(slave_rst_cam), 
    .sample_cam(slave_sample_cam));
	
  control_unit UUT3 (
    .clk_in(dcm_clk),
    .reset(reset),
    .master_adc(master_adc),
    .slave_adc(slave_bus),
    .misalign(mismatch_delay),
    .ready(ready));
  
  assign master_bus = (slave_write==0) ? 1'b0 : 1'bz;
  assign slave_bus = (master_write==0) ? 1'b0 : 1'bz;
  
  	initial forever #25 dcm_clk  = ~dcm_clk;
    initial // Master
        begin
			dcm_clk = 0;
          	system_rst = 1;	
			master_adc = 1;
          	#100
          	system_rst = 0;
			#1400
          
          	master_adc = 0;
          	#1290
          	master_adc = 1;
          
            #740
          
          	master_adc = 0;
          	
        end
  
      initial // Slave
        begin
          	slave_adc = 1;
			#1600
          
          	slave_adc = 0;
          	#1290
          	slave_adc = 1;
          
            #740
          
          	slave_adc = 0;
        end
  
  always @ (*)
    begin
      if(slave_bus == 1'b0 && master_write)
        slave_write <= #delay_interconnect 0;
      else
        slave_write <= #delay_interconnect 1;
    end
  
  always @ (*)
    begin        
      if(master_bus  == 1'b0 && slave_write)
        master_write <= #delay_interconnect 0;
      else
        master_write <= #delay_interconnect 1;
    end
    
  
  
  initial begin
    slave_write = 1;
    master_write = 1;
    $dumpfile ("mux.vcd");
    $dumpvars;
  end

  initial begin 
    #4500;
    $finish;
  end 
endmodule
