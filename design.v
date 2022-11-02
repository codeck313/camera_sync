module control_unit(
 input wire clk_in,
 input wire reset,
 input wire master_adc,
 input wire slave_adc,
 output reg [15:0] misalign,
 output reg ready);

  reg [15:0] cnt;
  reg cnt_en, cnt_reset;
  reg master_adc_prev, slave_adc_prev;
  wire master_adc_r, slave_adc_f;
  assign master_adc_r = master_adc > master_adc_prev;
  assign slave_adc_f = slave_adc < slave_adc_prev;

  always @(posedge clk_in)
    begin
      master_adc_prev <= master_adc;
      slave_adc_prev <= slave_adc;
    end
  
  
  always @(posedge clk_in)
    begin
      if (reset)
        begin
          { ready, cnt_en } <= 2'b00;
          misalign <= 0;
        end 
      else 
        begin
          if ((master_adc == 1'b0) && (slave_adc == 1'b1))
          { ready, cnt_reset } <= 2'b01;
          else
            cnt_reset <= 1'b0;

          // Both are ON 
          if (master_adc_r && slave_adc_f)
            begin
              misalign <= 0;
              { ready, cnt_en } <= 2'b10;
            end
          else if ((master_adc_r && !slave_adc_f) || (!master_adc_r && slave_adc_f))
            begin
              { ready, cnt_en } <= 2'b01;
            end

          if ((cnt_en == 1'b1) && (master_adc_r || slave_adc_f))
            begin
              { ready, cnt_en } <= 2'b10;
              misalign <= master_adc_r ? (-(cnt>>1)) : (cnt>>1);
            end
        end
    end

  always @(posedge clk_in) /* counter */
    if ((cnt_reset) || (reset))
      cnt <= 0;
  else if (cnt_en)
    cnt <= cnt + 1;

endmodule



module slave_module(
  input wire rst_FSM,
  input wire pix_clk, 
  input wire end_adc, 
  inout wire feedback_master, 
  output reg rst_cam, 
  output reg sample_cam);
	  
  // delay variables 25ns for each pulse
  reg [5:0] delay_counter;
  parameter us1_delay = 6'd4; //40
  parameter us2_delay = 6'd8; //40
  
  // Control variables for module
  reg write;
  reg sample_eligible, sample_rcv;
  
  // Sample State var and params
  reg [1:0] sample_state;
  parameter wait_rst = 2'b00, send_sample = 2'b01, recv_adc = 2'b10;
  
  // Sample Integration var and params
  reg [1:0] integration_state;
  parameter send_rst = 2'b00, wait_8 = 2'b01, wait_high_sample = 2'b10, wait_low_sample = 2'b11;
  
  assign feedback_master = (write) ? 1'b0 : 1'bz;
  
  
  // Sample FSM
  always @ (posedge pix_clk)
    begin
      if (rst_FSM)
        begin
          $display("verytime");
          write <= 0;
          sample_eligible <= 0;
          sample_rcv <= 0;

          delay_counter <= 0;

          sample_state <= wait_rst;
          sample_cam <= 0;

          integration_state <= send_rst;
          rst_cam <= 0;
        end 
      else 
        begin
          case(sample_state)
            wait_rst:
              begin
                if (sample_eligible && end_adc)
                  begin
                    sample_state <= send_sample;
                    sample_eligible <= 0;
                    write <= 1;
                  end
              end
            send_sample:
              begin
                //             write <= 0;
                if (delay_counter==us1_delay)
                  begin
                    sample_state <= recv_adc;
                    delay_counter <= 6'd0;
                    sample_cam <= 0;
                    sample_rcv<=0;
                  end
                else if (write == 1)
                  write <= 0;
                else if (!feedback_master||sample_rcv)
                  begin
                    sample_cam <= 1;
                    delay_counter <= delay_counter + 1;
                    sample_rcv<=1;
                  end

              end
            recv_adc:
              begin
                if(!end_adc)
                  sample_state <= wait_rst;
              end
            default: sample_state <= wait_rst;
          endcase  
        end
    end
  
  
  // Rst FSM
  always @ (posedge pix_clk)
    begin
      if(!rst_FSM)
        begin
          case(integration_state)
            send_rst:
              begin
                if (delay_counter==us2_delay)
                  begin
                    integration_state <= wait_8;
                    delay_counter<= 6'd0;
                    rst_cam <= 0;
                  end
                else
                  begin
                    rst_cam <= 1;
                    delay_counter <= delay_counter + 1;
                  end
              end

            wait_8:
              begin
                if (delay_counter==8)
                  begin
                    integration_state <= wait_high_sample;
                    delay_counter <= 6'd0;
                    sample_eligible <= 1;
                  end
                else
                  begin
                    delay_counter <= delay_counter + 1;
                  end
              end

            wait_high_sample:
              begin
                if (sample_cam)
                  integration_state <= wait_low_sample;
              end
            wait_low_sample:
              begin
                if(!sample_cam)
                  begin
                    if (delay_counter==7)
                      begin
                        integration_state <= send_rst;
                        delay_counter <= 6'd0;
                      end
                    else
                      begin
                        delay_counter <= delay_counter + 1;
                      end
                  end
              end

            default: integration_state <= send_rst;
          endcase 
        end
    end
endmodule


module master_module(
  input wire rst_FSM,
  input wire pix_clk, 
  input wire end_adc, 
  input wire [7:0] mismatch_delay, 
  input wire ready, 
  inout wire control_slave, 
  output reg rst_cam, 
  output reg sample_cam,
  output reg rst_cu);
  
  // delay variables 25ns for each pulse
  reg [8:0] delay_counter;
  parameter us1_delay = 6'd4; //40
  parameter us2_delay = 6'd8; //40
  
  // Control variables for module
  reg write;
  reg sample_eligible;
  reg [7:0] align_delay;
  reg first_cycle;
  
  // Sample State var and params
  reg [1:0] sample_state;
  parameter wait_rst = 2'b00, send_sample = 2'b01, recv_adc = 2'b10;
  
  // Sample Integration var and params
  reg [1:0] integration_state;
  parameter send_rst = 2'b00, wait_8 = 2'b01, wait_high_sample = 2'b10, wait_low_sample = 2'b11;
  
  assign control_slave = (write) ? 1'b0 : 1'bz;
  
  // Sample FSM
  always @ (posedge pix_clk)
    begin
      if (rst_FSM)
        begin
          $display("verytime");
          write = 0;
          sample_eligible = 0;

          delay_counter= 8'd0;

          sample_state = wait_rst;
          sample_cam = 0;

          integration_state = send_rst;
          rst_cam = 0;
          rst_cu = 0;

          first_cycle = 1;
        end 
      else
        begin
          case(sample_state)
            wait_rst:
              begin
                if (sample_eligible && end_adc && (ready||first_cycle))
                  begin
                    sample_state <= send_sample;
                    sample_eligible <= 0;
                    align_delay <= first_cycle? 7'd0 : mismatch_delay;
                    rst_cu <= 1;
                    first_cycle <= 0;
                    //                 store_slave_adc <=0;
                  end
              end
            send_sample:
              begin
                if (delay_counter == align_delay + 1) // +1 -> due to sampling @ slave of sample command from master
                  sample_cam <= 1;

                if (delay_counter==us1_delay + align_delay + 1) // Turn off master pulse
                  begin 
                    sample_state <= recv_adc;
                    delay_counter <= 6'd0;
                    //                 write = 0;
                    sample_cam <= 0;
                  end
                else
                  begin
                    if (delay_counter >= us1_delay)
                      write <= 0;
                    else
                      write <= 1;
                    //                 sample_cam <= 1;
                    delay_counter <= delay_counter + 1;
                  end
              end
            recv_adc:
              begin
                if(!end_adc)
                  begin
                    sample_state <= wait_rst;
                    rst_cu <= 0;
                  end
              end
            default: sample_state <= wait_rst;
          endcase 
        end
    end
  
  
  // Rst FSM
  always @ (posedge pix_clk)
    begin
      if (!rst_FSM)
        begin
          case(integration_state)
            send_rst:
              begin
                if (delay_counter==us2_delay)
                  begin
                    integration_state <= wait_8;
                    delay_counter<= 6'd0;
                    rst_cam <= 0;
                  end
                else
                  begin
                    rst_cam <= 1;
                    delay_counter <= delay_counter + 1;
                  end
              end

            wait_8:
              begin
                if (delay_counter==8)
                  begin
                    integration_state <= wait_high_sample;
                    delay_counter <= 6'd0;
                    sample_eligible <= 1;
                  end
                else
                  begin
                    delay_counter <= delay_counter + 1;
                  end
              end

            wait_high_sample:
              begin
                if (sample_cam)
                  integration_state <= wait_low_sample;
              end
            wait_low_sample:
              begin
                if(!sample_cam)
                  begin
                    if (delay_counter==7)
                      begin
                        integration_state <= send_rst;
                        delay_counter <= 6'd0;
                      end
                    else
                      begin
                        delay_counter <= delay_counter + 1;
                      end
                  end
              end

            default: integration_state <= send_rst;
          endcase 
        end
    end
endmodule
