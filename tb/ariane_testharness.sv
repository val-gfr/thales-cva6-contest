// Copyright (c) 2020 Thales.
// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 19.03.2017
//
// Additional contributions by:
//         Sebastien Jacq - sjthales on github.com
//
// Description: Test-harness for Ariane
//              Instantiates an AXI-Bus and memories
//
// =========================================================================== //
// Revisions  :
// Date        Version  Author       Description
// 2020-10-06  0.1      S.Jacq       modification for CVA6 softcore
// =========================================================================== //

module ariane_testharness #(
  parameter int unsigned AXI_USER_WIDTH    = 1,
  parameter int unsigned AXI_ADDRESS_WIDTH = 64,
  parameter int unsigned AXI_DATA_WIDTH    = 64,
  parameter int unsigned NUM_WORDS         = 2**25,         // memory size
  parameter bit          StallRandomOutput = 1'b0,
  parameter bit          StallRandomInput  = 1'b0
) (
  input  logic        clk_i,
  input  logic        rtc_i,
  input  logic        rst_ni,
  input  logic        jtag_TCK,
  input  logic        jtag_TMS,
  input  logic        jtag_TDI,
  input  logic        jtag_TRSTn,
  output logic        jtag_TDO_data,
  output logic        jtag_TDO_driven
);

  // disable test-enable
  logic        test_en;
  logic        ndmreset;
  logic        ndmreset_n;
  logic        debug_req_core;

  int          jtag_enable;
  logic        init_done;
  logic [31:0] jtag_exit, dmi_exit;

  logic        debug_req_valid;
  logic        debug_req_ready;
  logic        debug_resp_valid;
  logic        debug_resp_ready;

  logic        jtag_req_valid;

  logic        jtag_resp_ready;
  logic        jtag_resp_valid;

  dm::dmi_req_t  jtag_dmi_req;
  dm::dmi_req_t  debug_req;
  dm::dmi_resp_t debug_resp;

  assign test_en = 1'b0;


  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH   ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH      ),
    .AXI_ID_WIDTH   ( ariane_soc::IdWidth ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH      )
  ) slave[ariane_soc::NrSlaves-1:0]();

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           )
  ) master[ariane_soc::NB_PERIPHERALS-1:0]();

  rstgen i_rstgen_main (
    .clk_i        ( clk_i                ),
    .rst_ni       ( rst_ni & (~ndmreset) ),
    .test_mode_i  ( test_en              ),
    .rst_no       ( ndmreset_n           ),
    .init_no      (                      ) // keep open
  );

  // ---------------
  // Debug
  // ---------------
  assign init_done = rst_ni;

  assign debug_req_valid     = jtag_req_valid;
  assign debug_resp_ready    = jtag_resp_ready;
  assign debug_req           = jtag_dmi_req;
  assign jtag_resp_valid     = debug_resp_valid;

  dmi_jtag i_dmi_jtag (
    .clk_i            ( clk_i           ),
    .rst_ni           ( rst_ni          ),
    .testmode_i       ( test_en         ),
    .dmi_req_o        ( jtag_dmi_req    ),
    .dmi_req_valid_o  ( jtag_req_valid  ),
    .dmi_req_ready_i  ( debug_req_ready ),
    .dmi_resp_i       ( debug_resp      ),
    .dmi_resp_ready_o ( jtag_resp_ready ),
    .dmi_resp_valid_i ( jtag_resp_valid ),
    .dmi_rst_no       (                 ), // not connected
    .tck_i            ( jtag_TCK        ),
    .tms_i            ( jtag_TMS        ),
    .trst_ni          ( jtag_TRSTn      ),
    .td_i             ( jtag_TDI        ),
    .td_o             ( jtag_TDO_data   ),
    .tdo_oe_o         ( jtag_TDO_driven )
  );


  ariane_axi::req_t    dm_axi_m_req;
  ariane_axi::resp_t   dm_axi_m_resp;

  logic                dm_slave_req;
  logic                dm_slave_we;
  logic [64-1:0]       dm_slave_addr;
  logic [64/8-1:0]     dm_slave_be;
  logic [64-1:0]       dm_slave_wdata;
  logic [64-1:0]       dm_slave_rdata;

  logic                dm_master_req;
  logic [64-1:0]       dm_master_add;
  logic                dm_master_we;
  logic [64-1:0]       dm_master_wdata;
  logic [64/8-1:0]     dm_master_be;
  logic                dm_master_gnt;
  logic                dm_master_r_valid;
  logic [64-1:0]       dm_master_r_rdata;

  // debug module
  dm_top #(
    .NrHarts              ( 1                           ),
    .BusWidth             ( AXI_DATA_WIDTH              ),
    .SelectableHarts      ( 1'b1                        )
  ) i_dm_top (
    .clk_i                ( clk_i                       ),
    .rst_ni               ( rst_ni                      ), // PoR
    .testmode_i           ( test_en                     ),
    .ndmreset_o           ( ndmreset                    ),
    .dmactive_o           (                             ), // active debug session
    .debug_req_o          ( debug_req_core              ),
    .unavailable_i        ( '0                          ),
    .hartinfo_i           ( {ariane_pkg::DebugHartInfo} ),
    .slave_req_i          ( dm_slave_req                ),
    .slave_we_i           ( dm_slave_we                 ),
    .slave_addr_i         ( dm_slave_addr               ),
    .slave_be_i           ( dm_slave_be                 ),
    .slave_wdata_i        ( dm_slave_wdata              ),
    .slave_rdata_o        ( dm_slave_rdata              ),
    .master_req_o         ( dm_master_req               ),
    .master_add_o         ( dm_master_add               ),
    .master_we_o          ( dm_master_we                ),
    .master_wdata_o       ( dm_master_wdata             ),
    .master_be_o          ( dm_master_be                ),
    .master_gnt_i         ( dm_master_gnt               ),
    .master_r_valid_i     ( dm_master_r_valid           ),
    .master_r_rdata_i     ( dm_master_r_rdata           ),
    .dmi_rst_ni           ( rst_ni                      ),
    .dmi_req_valid_i      ( debug_req_valid             ),
    .dmi_req_ready_o      ( debug_req_ready             ),
    .dmi_req_i            ( debug_req                   ),
    .dmi_resp_valid_o     ( debug_resp_valid            ),
    .dmi_resp_ready_i     ( debug_resp_ready            ),
    .dmi_resp_o           ( debug_resp                  )
  );


  axi2mem #(
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           )
  ) i_dm_axi2mem (
    .clk_i      ( clk_i                     ),
    .rst_ni     ( rst_ni                    ),
    .slave      ( master[ariane_soc::Debug] ),
    .req_o      ( dm_slave_req              ),
    .we_o       ( dm_slave_we               ),
    .addr_o     ( dm_slave_addr             ),
    .be_o       ( dm_slave_be               ),
    .data_o     ( dm_slave_wdata            ),
    .data_i     ( dm_slave_rdata            )
  );

  axi_master_connect i_dm_axi_master_connect (
    .axi_req_i(dm_axi_m_req),
    .axi_resp_o(dm_axi_m_resp),
    .master(slave[1])
  );

  axi_adapter #(
    .DATA_WIDTH            ( AXI_DATA_WIDTH            )
  ) i_dm_axi_master (
    .clk_i                 ( clk_i                     ),
    .rst_ni                ( rst_ni                    ),
    .req_i                 ( dm_master_req             ),
    .type_i                ( ariane_axi::SINGLE_REQ    ),
    .gnt_o                 ( dm_master_gnt             ),
    .gnt_id_o              (                           ),
    .addr_i                ( dm_master_add             ),
    .we_i                  ( dm_master_we              ),
    .wdata_i               ( dm_master_wdata           ),
    .be_i                  ( dm_master_be              ),
    .size_i                ( 2'b11                     ), // always do 64bit here and use byte enables to gate
    .id_i                  ( '0                        ),
    .valid_o               ( dm_master_r_valid         ),
    .rdata_o               ( dm_master_r_rdata         ),
    .id_o                  (                           ),
    .critical_word_o       (                           ),
    .critical_word_valid_o (                           ),
    .axi_req_o             ( dm_axi_m_req              ),
    .axi_resp_i            ( dm_axi_m_resp             )
  );


  // ---------------
  // ROM
  // ---------------
  logic                         rom_req;
  logic [AXI_ADDRESS_WIDTH-1:0] rom_addr;
  logic [AXI_DATA_WIDTH-1:0]    rom_rdata;

  axi2mem #(
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           )
  ) i_axi2rom (
    .clk_i  ( clk_i                   ),
    .rst_ni ( ndmreset_n              ),
    .slave  ( master[ariane_soc::ROM] ),
    .req_o  ( rom_req                 ),
    .we_o   (                         ),
    .addr_o ( rom_addr                ),
    .be_o   (                         ),
    .data_o (                         ),
    .data_i ( rom_rdata               )
  );

  bootrom i_bootrom (
    .clk_i      ( clk_i     ),
    .req_i      ( rom_req   ),
    .addr_i     ( rom_addr  ),
    .rdata_o    ( rom_rdata )
  );

  // ------------------------------
  // Memory + Exclusive Access
  // ------------------------------
  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           )
  ) dram();

  logic                         req;
  logic                         we;
  logic [AXI_ADDRESS_WIDTH-1:0] addr;
  logic [AXI_DATA_WIDTH/8-1:0]  be;
  logic [AXI_DATA_WIDTH-1:0]    wdata;
  logic [AXI_DATA_WIDTH-1:0]    rdata;

  axi_riscv_atomics_wrap #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           ),
    .AXI_MAX_WRITE_TXNS ( 1  ),
    .RISCV_WORD_WIDTH   ( 64 )
  ) i_axi_riscv_atomics (
    .clk_i,
    .rst_ni ( ndmreset_n               ),
    .slv    ( master[ariane_soc::DRAM] ),
    .mst    ( dram                     )
  );

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           )
  ) dram_delayed();


  axi2mem #(
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_USER_WIDTH ( AXI_USER_WIDTH           )
  ) i_axi2mem (
    .clk_i  ( clk_i        ),
    .rst_ni ( ndmreset_n   ),
    .slave  ( dram ),
    .req_o  ( req          ),
    .we_o   ( we           ),
    .addr_o ( addr         ),
    .be_o   ( be           ),
    .data_o ( wdata        ),
    .data_i ( rdata        )
  );

  sram #(
    .DATA_WIDTH ( AXI_DATA_WIDTH ),
    .NUM_WORDS  ( NUM_WORDS      )
  ) i_sram (
    .clk_i      ( clk_i                                                                       ),
    .rst_ni     ( rst_ni                                                                      ),
    .req_i      ( req                                                                         ),
    .we_i       ( we                                                                          ),
    .addr_i     ( addr[$clog2(NUM_WORDS)-1+$clog2(AXI_DATA_WIDTH/8):$clog2(AXI_DATA_WIDTH/8)] ),
    .wdata_i    ( wdata                                                                       ),
    .be_i       ( be                                                                          ),
    .rdata_o    ( rdata                                                                       )
  );

  // ---------------
  // AXI Xbar
  // ---------------
  typedef logic [ariane_soc::NrRegion-1:0][ariane_soc::NB_PERIPHERALS-1:0][AXI_ADDRESS_WIDTH-1:0] addr_map_t;
  
  axi_node_intf_wrap #(
    .NB_SLAVE           ( ariane_soc::NrSlaves       ),
    .NB_MASTER          ( ariane_soc::NB_PERIPHERALS ),
    .NB_REGION          ( ariane_soc::NrRegion       ),
    .AXI_ADDR_WIDTH     ( AXI_ADDRESS_WIDTH          ),
    .AXI_DATA_WIDTH     ( AXI_DATA_WIDTH             ),
    .AXI_USER_WIDTH     ( AXI_USER_WIDTH             ),
    .AXI_ID_WIDTH       ( ariane_soc::IdWidth        )
  ) i_axi_xbar (
    .clk          ( clk_i      ),
    .rst_n        ( ndmreset_n ),
    .test_en_i    ( test_en    ),
    .slave        ( slave      ),
    .master       ( master     ),
    .start_addr_i (addr_map_t'({
      ariane_soc::DebugBase,
      ariane_soc::ROMBase,
      ariane_soc::CLINTBase,
      ariane_soc::PLICBase,
      ariane_soc::UARTBase,
      ariane_soc::TimerBase,
      ariane_soc::SPIBase,
      ariane_soc::EthernetBase,
      ariane_soc::GPIOBase,
      ariane_soc::DRAMBase
    })),
    .end_addr_i   (addr_map_t'({
      ariane_soc::DebugBase    + ariane_soc::DebugLength - 1,
      ariane_soc::ROMBase      + ariane_soc::ROMLength - 1,
      ariane_soc::CLINTBase    + ariane_soc::CLINTLength - 1,
      ariane_soc::PLICBase     + ariane_soc::PLICLength - 1,
      ariane_soc::UARTBase     + ariane_soc::UARTLength - 1,
      ariane_soc::TimerBase    + ariane_soc::TimerLength - 1,
      ariane_soc::SPIBase      + ariane_soc::SPILength - 1,
      ariane_soc::EthernetBase + ariane_soc::EthernetLength -1,
      ariane_soc::GPIOBase     + ariane_soc::GPIOLength - 1,
      ariane_soc::DRAMBase     + ariane_soc::DRAMLength - 1
    })),
    .valid_rule_i (ariane_soc::ValidRule)
  );

  // ---------------
  // CLINT
  // ---------------
  logic ipi;
  logic timer_irq;

  ariane_axi::req_t    axi_clint_req;
  ariane_axi::resp_t   axi_clint_resp;

  clint #(
    .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH        ),
    .AXI_DATA_WIDTH ( AXI_DATA_WIDTH           ),
    .AXI_ID_WIDTH   ( ariane_soc::IdWidthSlave ),
    .NR_CORES       ( 1                        )
  ) i_clint (
    .clk_i       ( clk_i          ),
    .rst_ni      ( ndmreset_n     ),
    .testmode_i  ( test_en        ),
    .axi_req_i   ( axi_clint_req  ),
    .axi_resp_o  ( axi_clint_resp ),
    .rtc_i       ( rtc_i          ),
    .timer_irq_o ( timer_irq      ),
    .ipi_o       ( ipi            )
  );

  axi_slave_connect i_axi_slave_connect_clint (
    .axi_req_o(axi_clint_req),
    .axi_resp_i(axi_clint_resp),
    .slave(master[ariane_soc::CLINT])
  );

  // ---------------
  // Peripherals
  // ---------------
  logic tx, rx;
  logic [1:0] irqs;

  ariane_peripherals #(
    .AxiAddrWidth ( AXI_ADDRESS_WIDTH        ),
    .AxiDataWidth ( AXI_DATA_WIDTH           ),
    .AxiIdWidth   ( ariane_soc::IdWidthSlave ),
    .InclUART     ( 1'b1                     ),
    .InclSPI      ( 1'b0                     ),
    .InclEthernet ( 1'b0                     )
  ) i_ariane_peripherals (
    .clk_i     ( clk_i                        ),
    .rst_ni    ( ndmreset_n                   ),
    .plic      ( master[ariane_soc::PLIC]     ),
    .uart      ( master[ariane_soc::UART]     ),
    .spi       ( master[ariane_soc::SPI]      ),
    .ethernet  ( master[ariane_soc::Ethernet] ),
    .timer     ( master[ariane_soc::Timer]    ),
    .irq_o     ( irqs                         ),
    .rx_i      ( rx                           ),
    .tx_o      ( tx                           ),
    .eth_txck  ( ),
    .eth_rxck  ( ),
    .eth_rxctl ( ),
    .eth_rxd   ( ),
    .eth_rst_n ( ),
    .eth_tx_en ( ),
    .eth_txd   ( ),
    .phy_mdio  ( ),
    .eth_mdc   ( ),
    .mdio      ( ),
    .mdc       ( ),
    .spi_clk_o ( ),
    .spi_mosi  ( ),
    .spi_miso  ( ),
    .spi_ss    ( )
  );

  uart_bus #(.BAUD_RATE(115200), .PARITY_EN(0)) i_uart_bus (.rx(tx), .tx(rx), .rx_en(1'b1));

  // ---------------
  // Core
  // ---------------
  ariane_axi::req_t    axi_ariane_req;
  ariane_axi::resp_t   axi_ariane_resp;

  ariane #(
    .ArianeCfg  ( ariane_soc::ArianeSocCfg )
  ) i_ariane (
    .clk_i                ( clk_i               ),
    .rst_ni               ( ndmreset_n          ),
    .boot_addr_i          ( ariane_soc::ROMBase ), // start fetching from ROM
    .hart_id_i            ( '0                  ),
    .irq_i                ( irqs                ),
    .ipi_i                ( ipi                 ),
    .time_irq_i           ( timer_irq           ),
    .debug_req_i          ( debug_req_core      ),
    .axi_req_o            ( axi_ariane_req      ),
    .axi_resp_i           ( axi_ariane_resp     )
  );

  axi_master_connect i_axi_master_connect_ariane (
    .axi_req_i(axi_ariane_req),
    .axi_resp_o(axi_ariane_resp),
    .master(slave[0])
  );

  // -------------
  // Simulation Helper Functions
  // -------------
  // check for response errors
  always_ff @(posedge clk_i) begin : p_assert
    if (axi_ariane_req.r_ready &&
      axi_ariane_resp.r_valid &&
      axi_ariane_resp.r.resp inside {axi_pkg::RESP_DECERR, axi_pkg::RESP_SLVERR}) begin
      $warning("R Response Errored");
    end
    if (axi_ariane_req.b_ready &&
      axi_ariane_resp.b_valid &&
      axi_ariane_resp.b.resp inside {axi_pkg::RESP_DECERR, axi_pkg::RESP_SLVERR}) begin
      $warning("B Response Errored");
    end
  end
endmodule
