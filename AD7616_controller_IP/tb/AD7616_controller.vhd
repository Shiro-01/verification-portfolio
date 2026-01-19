-- ############################################################
-- General Notes (ADC Operating Principle – AD7616)
-- ############################################################
-- • The high-speed ADC IP is designed to operate in
--   **Hardware Mode** , ** Parallel interface mode** & **Burst sequence Mode** (see AD7616 TRM). 
--   Design for 2 Differnt Chips sharing the same interface
--
-- • All timing constraints (CONVST, BUSY, CS, RD) are respected
--   according to the AD7616 datasheet.
-- ############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AD7616_controller is
    port (
        -- ################# Global #################
        clk         : in  std_logic;                          -- 100 MHz PL clock
        rst_n       : in  std_logic;                          -- Active-low reset
        timestamp   : in  std_logic_vector(63 downto 0);      -- Global PL timestamp

        -- ################# ADC Interface #################
        adc_seqen   : out std_logic;                          -- Sequencer enable (hardware mode)
        adc_chsel   : out std_logic_vector(2 downto 0);       -- End channel select (0..7)
        adc_rst_n   : out std_logic;                          -- ADC reset (latches HW config)

        adc_convst  : out std_logic;                          -- Conversion start (shared)
        adc_busy_or : in  std_logic;                          -- OR'ed BUSY from both ADC chips

        adc_cs_n    : out std_logic_vector(1 downto 0);       -- Chip select (never assert both. the buss is shared between the two chips)
        adc_rd_n    : out std_logic;                          -- Read strobe (parallel interface)
        adc_data    : in  std_logic_vector(15 downto 0);      -- ADC data bus

        -- ################# AXI-Stream Master Interface #################
        m_axis_tdata  : out std_logic_vector(31 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );
end entity AD7616_controller;

architecture rtl of AD7616_controller is
   
    -- #####  Constants & waiting periods  ###ä# --
    constant ADC_RST_N_LOW      : unsigned(23 downto 0) := x"000095";            -- reset minimum hold low period. setted to  1500 ns = 150 * 10e-9 @ 100 MHz (1200 ns required)
    constant DEVICE_SETUP_TIME  : unsigned(23 downto 0) := x"1e847f";            -- Minmumn waiting period required before sending convst signal (15 ms required), 20 is used!
    constant CONVST_HIGH_PERIOD : unsigned(23 downto 0) := x"000005";            -- Minimum high pulse width  of CONVS, required 50 ns
    constant DOUT_SETUP         : unsigned(23 downto 0) := x"000004";            -- minimum delay betweeen the falling edge of RD line and the safe data access. required min 30 ns, for safty 40 ns 
    constant TDOUT_3STATE       : unsigned(23 downto 0) := x"000002";            -- Minimum clearance time between the rising Edge of CS and cleaning the Data bus

    type state_t is (
        --------------------------------------------------------------------
        -- Reset & setup States
        --------------------------------------------------------------------
        RESET,                            -- Reset stay low for 1.5 µsec
        SET_UP_TIME,                      -- set up time waiting for 20 ms
        --------------------------------------------------------------------
        -- Conversion control States
        --------------------------------------------------------------------
        START_CONV,                       -- Send the CONVST signal to both boards same time. And capture the time stamp of Sending
        CONVST_HIGH,                      -- stay high for min 50 ns , we have enough time to busy signals to go high. they need at max 32 ns to get high
        BUSY_HIGH_TIMEOUT_CHECK,          -- checks if the ORed Busy signal when high or not. otherwise reset
        WAIT_BUSY_FALL,                   -- Waiting till ORed Busy goes low to indicate the end of the conversion for both chips
        --------------------------------------------------------------------
        -- Header Send States
        --------------------------------------------------------------------
        SEND_TS_HIGH,                     -- Sending high part of the time stamp
        SEND_TS_LO,                       -- Sending low part of the time stamp
        SEND_RESERVED_1,                  -- Sending 1st reserved word
        SEND_RESERVED_2,                  -- Sending Second reserved word. There is minimum timinig requirnment between falling Edge of buy and the CS falling edge. we harnesed this time to send the header data
        --------------------------------------------------------------------
        -- Read chip 0 States
        --------------------------------------------------------------------
        SEL_CHIP0,                        -- Selecting first ADC chip (Chip 0) by assrting CS lines. timerequirement is met
        ASSERT_RD_CHIP0,                  -- Assereting RD line of the first chip to start loading the first conversied word. Minimum time requiremnt between falling edges of (cs and RD) is 10 ns. (Met by our clk 100 MHz)
        READ_WORDS_CHIP0,                 -- Reading the first Word from Chip 0. Minimum set up time for the data after the falling edge of RD is 30 ns. is met!
        SEND_WORD_CHIP0,                  -- Sending the First *PACKED* Word after two reads from the chip 0 
        SEND_AWK0,                        -- Waiting for Hand shake and deciding weather we are done with Chip 0 and move to the second chip OR loop back to Read chip 0 states
        --------------------------------------------------------------------
        -- Read chip 1 States
        -------------------------------------------------------------------- 
        SEL_CHIP1,                       -- Selecting Second ADC chip (Chip 1) by assrting CS lines. time equirement is minimum 10 ns between rsising edge of (rd and cs) and another 11 ns (max) to clean the bus lines. 
        ASSERT_RD_CHIP1,                 -- Assereting RD line of the second chip to start loading the first conversied word. Minimum time requiremnt between falling edges of (cs and RD) is 10 ns. (Met by our clk 100 MHz)
        READ_WORDS_CHIP1,                -- Reading the fisecond Word from Chip 1. Minimum set up time for the data after the falling edge of RD is 30 ns. is met!
        SEND_WORD_CHIP1,                 -- Sending the First *PACKED* Word after two reads from the chip 1
        SEND_AWK1,                       -- Waiting for Hand shake and deciding weather we are done with Chip 1 and loop back to START_CONV OR loop back to Read chip 1 states
        UNSEL_CHIP2                      -- Un-seleting the second chip by coresponding CS Line.  time equirement is minimum 10 ns between rsising edge of (rd and cs) is met. Also a sainty 20 ns delay for clearing the data buss (Not really required as a new conv is starting afterwars)
    );


    -- ################ ADC Controller FSM Signals ##################### -- 
    signal state: state_t := RESET;
        -- ############ ADC Signals ########### --
        signal adc_convst_r : std_logic                    := '0'; 
        signal adc_cs_n_r   : std_logic_vector(1 downto 0) := "11"; 
        signal adc_rd_n_r   : std_logic                    := '1';
        signal adc_rst_n_r  : std_logic                    := '1'; 
    
        -- ###### AXI stream interface ######## --
        signal m_axis_tdata_r  : std_logic_vector(31 downto 0); 
        signal m_axis_tvalid_r : std_logic := '0'; 
        signal m_axis_tlast_r  : std_logic := '0'; 
    
        -- ##### others ###### -- 
        signal timestamp_r       : std_logic_vector(63 downto 0) := (others => '0');   -- this signal is to latch the timestamp at the moment we send convst signal. 
        signal adc_data_register : std_logic_vector(31 downto 0) := (others => '0');   -- A 32 bit regsiter where we  collect two 16 bit words to send at once
        signal phase             : std_logic := '0';                                   -- a flage used to indicate if the second word of the ADC has read or not!
        signal read_count        : integer range 0 to 16 := 0;                         -- used to mark the end of read times
        signal counter           : unsigned(23 downto 0) := (others => '0');           -- counter that used the waiting periods
    
    -- ##################### synchroniszers signals ##################### -- 
    signal adc_busy_or_r        : std_logic;
    signal adc_busy_or_sync     : std_logic; 
    signal adc_busy_or_sync_dly : std_logic;

begin
    -- #################### combinational part ################### -- 
    adc_seqen <= '1';                               -- always enable the seqancer
    adc_chsel <= "111";                             -- set the last channel of the seqnycer to channel number 7 (meaning go through all the channals)

    -- ################ signals to port Assignations ############# --
    adc_convst <= adc_convst_r;
    adc_cs_n   <= adc_cs_n_r; 
    adc_rd_n   <= adc_rd_n_r; 
    adc_rst_n  <= adc_rst_n_r;

    m_axis_tdata  <=  m_axis_tdata_r; 
    m_axis_tvalid <= m_axis_tvalid_r;
    m_axis_tlast  <= m_axis_tlast_r;


    --  ############### synchroniszers PRocesses  ################### --
    busy_or_synchronizer : process(clk) 
    begin   
        if rising_edge(clk) then
            if rst_n = '0' then 
                adc_busy_or_r        <= '0';
                adc_busy_or_sync     <= '0';
                adc_busy_or_sync_dly <= '0';
            else 
                adc_busy_or_r        <= adc_busy_or;
                adc_busy_or_sync     <= adc_busy_or_r; 
                adc_busy_or_sync_dly <= adc_busy_or_sync;
            end if;
        end if;
    end process busy_or_synchronizer; 

    -- ################ ADC controller FSM ####################### -- 
    adc_controller_fsm : process(clk) is 
    begin
        if rising_edge(clk) then 
            if rst_n = '0' then 
                -- ############ ADC Signals Reset########### --
                adc_rst_n_r <= '1'; 
                adc_convst_r <= '0';
                adc_cs_n_r <= (others => '1');
                adc_rd_n_r <= '1';
                
                -- ###### AXI stream interface  Reset ######## --
                m_axis_tvalid_r <= '0';
                m_axis_tlast_r <= '0';
                m_axis_tdata_r <= (others => '0');
                
                -- ##### Others Reset###### -- 
                counter <= (others => '0');
                timestamp_r  <= (others => '0'); 
                adc_data_register <= (others => '0');
                phase <= '0';
                read_count <= 0;
                
                state <= RESET;
            else 
                case state is 
                    --------------------------------------------------------------------
                    -- Reset & Setup
                    --------------------------------------------------------------------
                    when RESET =>
                        adc_rst_n_r  <= '0';
                        adc_convst_r <= '0';

                        if counter < ADC_RST_N_LOW then
                            counter <= counter + 1; 
                        else 
                            counter <= (others => '0'); 
                            adc_rst_n_r <= '1';
                            state       <= SET_UP_TIME;
                        end if; 

                    when SET_UP_TIME => 
                        counter <= counter + 1;
                        if counter >=  DEVICE_SETUP_TIME then 
                            counter <= (others => '0');
                            state   <= START_CONV;
                        end if;
                    
                    --------------------------------------------------------------------
                    -- Conversion control (both chips share CONVST,and other signals' buss, BUSY is OR-gated)
                    --------------------------------------------------------------------
                    when START_CONV =>
                        adc_convst_r <= '1'; 
                        timestamp_r  <= timestamp;    -- capture the time stamp we gave hte convesion signal at
                        state        <= CONVST_HIGH; 
                    
                    when CONVST_HIGH =>               -- wait for minimum high time 50 ns
                        counter <= counter + 1;
                        if counter >= CONVST_HIGH_PERIOD then 
                            adc_convst_r <= '0';
                            counter      <= (others => '0');
                            state        <= BUSY_HIGH_TIMEOUT_CHECK;
                        end if;

                    when BUSY_HIGH_TIMEOUT_CHECK => 
                        -- sainty check to make sure the ADC has responded. otherwise reset it. According to data sheet, it should go high at max of 32 ns. and as we wait for 50 ns already for convst high. the time has already passed. so reset if stall
                        if adc_busy_or_sync = '1' then
                            state <= WAIT_BUSY_FALL;
                        else 
                            state <= RESET; 
                        end if;

                    when WAIT_BUSY_FALL => 
                        if adc_busy_or_sync_dly = '1' and adc_busy_or_sync = '0' then   -- both ADCs have finished their conversions 
                            state <= SEND_TS_HIGH;                                      -- note, once busy or goes low, we need 20 ns before setting any CS low. it should be already satisfied due to the synchroniszer. but for mroe safty will send the time stamps now and within that will assert cs
                        end if; 
                    
                    --------------------------------------------------------------------
                    -- SEND 64-bit timestamp header (2 beats of 32-bit) + 2 reserved words 
                    -- Emits: TS[31:0], TS[63:32], and two reserved words (0)
                    --------------------------------------------------------------------
                    when SEND_TS_HIGH =>
                        m_axis_tdata_r  <= timestamp_r(63 downto 32);
                        m_axis_tvalid_r <= '1';
                        state           <= SEND_TS_LO;     

                    when SEND_TS_LO => 
                        if m_axis_tready = '1' and m_axis_tvalid_r = '1' then
                            m_axis_tdata_r  <= timestamp_r(31 downto 0);
                            m_axis_tvalid_r <= '1';
                            state           <= SEND_RESERVED_1;
                        end if; 
                    
                    when SEND_RESERVED_1 => 
                        if m_axis_tready = '1' and m_axis_tvalid_r = '1' then
                            m_axis_tdata_r  <= (others => '0');
                            m_axis_tvalid_r <= '1';

                            state <= SEND_RESERVED_2;  
                        end if;

                    when SEND_RESERVED_2 => 
                        if m_axis_tready = '1' and m_axis_tvalid_r = '1' then
                            m_axis_tdata_r  <= (others => '0');
                            m_axis_tvalid_r <= '1';
                            
                            state <= SEL_CHIP0;  
                        end if;

                    --------------------------------------------------------------------
                    -- Read chip 0 (16 words)
                    --------------------------------------------------------------------
                    when SEL_CHIP0 => 
                        if m_axis_tready = '1' and m_axis_tvalid_r = '1' then
                            m_axis_tvalid_r <= '0';          -- de assert valid flag to  stop the transmision
                            -- by now, it is safe to assert CS. if no transimission, then we would have needed to wait for minimum 20 ns.
                            adc_cs_n_r <= "10";
                            state      <= ASSERT_RD_CHIP0;   -- Minimum period between  cs falling edge and rd falling edge is minmum 10 ns, and it is achieved automaicaly by updating rd in the next cycle as our freq is 100 MHz
                        end if;

                    when ASSERT_RD_CHIP0 => 
                        adc_rd_n_r <= '0';
                        if counter >= DOUT_SETUP then        -- DOUT_SETUP = 4 ticks @100 MHz is 40 ns (30 minmum DOUT_SETUP or trd low +10 margin). look at page 8 of the ADC TRM
                            counter <= (others => '0');
                            state   <= READ_WORDS_CHIP0;
                        else 
                            counter <= counter + 1; 
                        end if;

                    when READ_WORDS_CHIP0 => 
                        adc_data_register <= adc_data_register(31 downto 16) & adc_data; 
                        read_count        <= read_count + 1;
                        adc_rd_n_r        <= '1';            -- minimum period of high is 10 ns. -- satisfied as our clk is 100 MHz

                        if phase = '0' then
                            phase <= '1';
                            state <= ASSERT_RD_CHIP0;        -- get second half
                        else
                            phase <= '0';
                            state <= SEND_WORD_CHIP0;        -- have full 32-bit word
                        end if;
                    
                    when SEND_WORD_CHIP0 =>
                        m_axis_tdata_r  <= adc_data_register;
                        m_axis_tvalid_r <= '1';
                        state           <= SEND_AWK0;

                    when SEND_AWK0 => 
                        if m_axis_tvalid_r = '1' and m_axis_tready = '1' then 
                            m_axis_tvalid_r <= '0';

                            if read_count >= 16 then 
                                read_count <= 0;
                                state      <= SEL_CHIP1;
                            else 
                                state      <= ASSERT_RD_CHIP0;
                            end if;
                        end if;

                --------------------------------------------------------------------
                -- Read chip 1 (16 words) + TLAST on last packed beat
                --------------------------------------------------------------------
                    when SEL_CHIP1 => 
                        --  Data sheet requires 10 ns before deaserting CS line,   --by the time we get to this state, 30 ns will have been already passed.
                        adc_cs_n_r <= "11";                 -- So, minimum period between cs falling eddge and rd falling edge (10 ns) is achieved!
                        if counter <= TDOUT_3STATE then     -- WE must hold the  cs line for at leat 11 ns to ensure the clearance of the data bus fromt the other Chip. here we are waiting 20 ns - 2 ticks
                            counter    <= (others => '0');
                            adc_cs_n_r <= "01";    
                            state      <= ASSERT_RD_CHIP1;
                         else
                             counter   <= counter + 1;
                         end if; 
                                
                    when ASSERT_RD_CHIP1 => 
                        adc_rd_n_r <= '0';                  --  Minimum timing requirement betweeb the falling edge of (CS & RD) is 10 ns. And it is met by the 100 MHz clk 
                        if counter >= DOUT_SETUP then
                            counter <= (others => '0');
                            state   <= READ_WORDS_CHIP1;
                        else 
                            counter <= counter + 1; 
                        end if;

                    when READ_WORDS_CHIP1 => 
                        adc_data_register <= adc_data_register(31 downto 16) & adc_data; 
                        read_count <= read_count + 1;
                        adc_rd_n_r <= '1';

                        if phase = '0' then
                            phase <= '1';
                            state <= ASSERT_RD_CHIP1;     -- get second half
                        else
                            phase <= '0';
                            state <= SEND_WORD_CHIP1;     -- have full 32-bit word
                        end if;
                
                    when SEND_WORD_CHIP1 =>
                        m_axis_tdata_r  <= adc_data_register;
                        m_axis_tvalid_r <= '1';

                        if read_count >= 16 then 
                            m_axis_tlast_r <= '1';
                        end if;

                        state <= SEND_AWK1;
                    
                    when SEND_AWK1 => 
                        if m_axis_tvalid_r = '1' and m_axis_tready = '1' then 
                            m_axis_tvalid_r <= '0';
                            m_axis_tlast_r  <= '0';

                            if read_count >= 16 then 
                                read_count <= 0;
                                state      <= UNSEL_CHIP2;
                            else 
                                state      <= ASSERT_RD_CHIP1;
                            end if;
                        end if;

                    when UNSEL_CHIP2 => 
                      --  Data sheet requires 10 ns before deaserting CS line (met as the clk is  100 MHz, and we have at least 3 cycles before to send data), 
                      -- Also needs max 11 ns after the deassertion to get the clean the data bus (not needed as we will start a new Conv tho, i  added it for sainty (just 20 ns)). 
                        adc_cs_n_r <= "11";
                        if counter <= TDOUT_3STATE then
                            state      <= START_CONV;
                            counter    <= (others => '0');
                        else
                             counter   <= counter + 1;
                        end if; 
                    
                    when others => 
                        state <= RESET;
                end case;
            end if;
        end if;
    end process adc_controller_fsm;
end architecture rtl;