library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--library osvvm;
--use osvvm.RandomPkg.all;

entity AD7616_controller_tb is
end entity;

architecture sim of AD7616_controller_tb is 

--****************  ADCs Signals *************
signal chip_clk : std_logic := '0';

signal chip_0_busy, chip_1_busy : std_logic;
signal adc_busy_or              : std_logic;

signal chip_0_data, chip_1_data              : std_logic_vector(15 downto 0);
signal data_bus             : std_logic_vector(15 downto 0);

signal selected_chip_0      : std_logic := '0';
signal selected_chip_1      : std_logic := '0';

signal cs0_n      : std_logic := '0';
signal cs1_n      : std_logic := '0';

-- ************ ADCs control signals from DUT (high speed adc controlelr) *********** -- 
signal adc_convst           : std_logic;
signal adc_rd_n             : std_logic;
signal adc_cs_n             : std_logic_vector(1 downto 0); -- "10" chip0, "01" chip1, "11" none
signal adc_seqen            : std_logic := '1';
signal adc_chsel            : std_logic_vector(2 downto 0) := "111";
signal adc_rst_n            : std_logic;                      
signal rdy_cnt              : integer := 0;

--***************** High speed ADC Contoller (DUT) other Signals ****************** --
signal controlelr_clk : std_logic := '0';
signal controller_rst_n : std_logic :='1'; 
signal controller_timestamp_counter    : unsigned(63 downto 0) := (others => '0');

signal controller_m_axis_tdata  : std_logic_vector(31 downto 0);
signal controller_m_axis_tvalid : std_logic;
signal controller_m_axis_tready : std_logic;
signal controller_m_axis_tlast  : std_logic;

-- shared variable RdyRand : RandomPType;

begin
	controlelr_clk <= not controlelr_clk after 5 ns; -- 100 MHz
	chip_clk <= not chip_clk after 0.5 ns; -- 1 GHz

    cs0_n <= adc_cs_n(0); 
    cs1_n <= adc_cs_n(1); 

    adc_busy_or <= chip_0_busy or chip_1_busy;

    data_bus <= chip_0_data when selected_chip_0 = '1' else
                chip_1_data when selected_chip_1 = '1' else
                (others => '0');


--******************** Instantiate ADC chips ****************
    chip_0 : entity work.ad7616_chip_simulator
    generic map (
            G_CHIP_ID           => 0,       -- one chip will be 0 the other will be 1. 
            G_CONV_CYCLES       => 520,     -- BUSY high length in clk cycles. in the data sheet it takes typ. 475 and at max 520 ns- the 
            G_NUM_HALFWORDS     => 16,      -- number of 16-bit reads per burst (chsel="111")
            G_MAX_FRAME_NUMBER  => 20,      -- max number of frames/ Conv request we reply to. 
            G_BUSY_SETUP_TIME   =>  33,     -- time till busy goes high
            G_DOUT_SETUP_TIME   =>  30      -- 30 ns for data to be read at max
        )

    port map (
            clk      => chip_clk,
            rst_n    => adc_rst_n,
            -- *********** Configureation ports *********- 
            chsel    => adc_chsel,           
            seqen    => adc_seqen,                             
            -- *********** control ports ************* -- 
            convst   => adc_convst,
            cs_n     => cs0_n,
            rd_n     => adc_rd_n,

            busy     => chip_0_busy,
            selected => selected_chip_0,   
            -- *********** data bus **************** --
            adc_data_bus  => chip_0_data
    );

    chip_1 : entity work.ad7616_chip_simulator
    generic map (
            G_CHIP_ID           => 1,       -- one chip will be 0 the other will be 1. 
            G_CONV_CYCLES       => 520,     -- BUSY high length in clk cycles. in the data sheet it takes typ. 475 and at max 520 ns- the 
            G_NUM_HALFWORDS     => 16,      -- number of 16-bit reads per burst (chsel="111")
            G_MAX_FRAME_NUMBER  => 20,      -- max number of frames/ Conv request we reply to. 
            G_BUSY_SETUP_TIME   =>  33,     -- time till busy goes high
            G_DOUT_SETUP_TIME   =>  30      -- 30 ns for data to be read at max
        )

    port map (
            clk      => chip_clk,
            rst_n    => adc_rst_n,
            -- *********** Configureation ports *********- 
            chsel    => adc_chsel,           
            seqen    => adc_seqen,                             
            -- *********** control ports ************* -- 
            convst   => adc_convst,
            cs_n     => cs1_n,
            rd_n     => adc_rd_n,

            busy     => chip_1_busy,
            selected => selected_chip_1,   
            -- *********** data bus **************** --
            adc_data_bus  => chip_1_data
    );


dut: entity work.AD7616_controller
port map(
        -- ################# Global #################
        clk         => controlelr_clk,                          -- 100 MHz PL clock
        rst_n       => controller_rst_n,                         -- Active-low reset
        timestamp   => std_logic_vector(controller_timestamp_counter),      -- Global PL timestamp

        -- ################# ADC Interface #################
        adc_seqen   => adc_seqen,                         -- Sequencer enable (hardware mode)
        adc_chsel   => adc_chsel,                         -- End channel select (0..7)
        adc_rst_n   => adc_rst_n,                         -- ADC reset (latches HW config)

        adc_convst  => adc_convst,                        -- Conversion start (shared)
        adc_busy_or => adc_busy_or,                       -- OR'ed BUSY from both ADC chips

        adc_cs_n    => adc_cs_n,                          -- Chip select (never assert both. the buss is shared between the to´wo chips)
        adc_rd_n    => adc_rd_n,                          -- Read strobe (parallel interface)
        adc_data    => data_bus,                           -- ADC data bus

        -- ################# AXI-Stream Master Interface #################
        m_axis_tdata  => controller_m_axis_tdata,
        m_axis_tvalid => controller_m_axis_tvalid,
        m_axis_tready => controller_m_axis_tready,
        m_axis_tlast  => controller_m_axis_tlast
);


--init_proc : process
--begin
--  RdyRand.InitSeed(1);  -- choose any seed (or change per test)
--  wait;                 -- stop this process forever
--end process;

--process(controlelr_clk)
--begin
--  if rising_edge(controlelr_clk) then
--    if rst_n='0' then
--      m_axis_tready <= '0';
--    else
--      -- 80% chance ready=1 (tune as you like)
--      m_axis_tready <= '1' when RdyRand.RandInt(0,99) < 80 else '0';
--    end if;
--  end if;
--end process;


process(controlelr_clk)
begin
  if rising_edge(controlelr_clk) then
      rdy_cnt <= rdy_cnt + 1;
      
      -- 50%: ready is high on even counts
      if (rdy_cnt mod 1) = 0 then
        controller_m_axis_tready <= '1';
      else
        controller_m_axis_tready <= '0';
    end if;
  end if;
end process;



timestamp : process(controlelr_clk)
begin
  if rising_edge(controlelr_clk) then
    controller_timestamp_counter <= controller_timestamp_counter + 1;
  end if;
end process;


end architecture sim;