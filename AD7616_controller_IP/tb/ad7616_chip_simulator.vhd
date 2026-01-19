--********************************************- 
-- This HDL is a simple simulator to AD7616 chip'S behaviour. 
-- Developed mainly for testing its high speed adc controller. 
-- Used to perform simulation that ensures that all timing constrains are met
-- 
-- Pls note:
-- the design is made for an input clk of 1 GHz
-- The design dones't fulfill all the timing constrains of the ADC. It has only some of it that 
-- is enough to run the simulation and check the timing constrains
--
-- Goal, to compare the resulted wave forms of the controller with the ones 
-- specified in the AD TRM page 7 and 8
--
-- Author: Abdelrahman Hewala
--********************************************************
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ad7616_chip_simulator is
    generic (
        G_CHIP_ID          : natural := 0;     -- one chip will be 0 the other will be 1. 
        G_CONV_CYCLES      : natural := 520;    -- BUSY high length in clk cycles. in the data sheet it takes typ. 475 and at max 520 ns- the 
        G_NUM_HALFWORDS    : natural := 16;    -- number of 16-bit reads per burst (chsel="111")
        G_MAX_FRAME_NUMBER : natural := 20;     -- max number of frames/ Conv request we reply to. 
        G_BUSY_SETUP_TIME  : natural := 33;
        G_DOUT_SETUP_TIME  : natural := 30        -- 30 ns for data to be read at max
    );

    port (
        -- *********** Rest and clk ************ -- 
        clk     : in std_logic;                              -- must be 1 GHz
        rst_n   : in std_logic; 

        -- *********** Configureation ports *********- 
        chsel   : in std_logic_vector(2 downto 0);           -- Note really programed, the following design is already set to 16
        seqen   : in std_logic;                              -- Note really programed, the following design is set to be always in burst sequence mode

        -- *********** control ports ************* -- 
        convst  : in std_logic; 
        cs_n      : in std_logic;
        rd_n      : in std_logic; 

        busy    : out std_logic;
        selected  : out std_logic;   -- this pin to allow us to muliplix two chips at once on the same bus later in the simulations

        -- *********** data bus **************** --
        adc_data_bus : out std_logic_vector(15 downto 0)
  );
end entity;

architecture sim of ad7616_chip_simulator is 

-- ********** Array lsit the will holds all the sampled data to be send ********* -- 
type samples_arr is array (0 to G_NUM_HALFWORDS-1) of std_logic_vector(15 downto 0);

-- ******************   samples registers  *******************- 
signal samples            : samples_arr := (others => (others => '0')); 
signal sample_idx         : natural range 0 to G_NUM_HALFWORDS := 0;            -- used to identify the sample number. later will be injected into the sample data it self
signal send_sample_idx    : natural range 0 to G_NUM_HALFWORDS := 0;            -- for tracking the sent samples
signal frame_id           : natural range 0 to G_MAX_FRAME_NUMBER := 0;         -- used to track number of conversions cycles we made/ frames we send



-- *********** Control register ****************** -- 
signal convst_d             : std_logic := '0'; 
signal selected_r           : std_logic := '0';
signal busy_r               : std_logic := '0'; 
signal busy_start           : std_logic := '0'; 
signal dout_setup           : std_logic := '0';    -- flag to indicate we can start set up counter for the data out

signal cs_n_d               : std_logic := '1';
signal rd_n_d               : std_logic := '1'; 
signal adc_data_bus_r       : std_logic_vector(15 downto 0) := (others => '0'); 

--***************** counters ******************* -- 
signal busy_setup_counter      : natural range 0 to 33 := 0;                        -- counter for busy set up time 
signal conversion_time_counter : natural range 0 to G_CONV_CYCLES - 1;              -- counter for busy high time
signal dout_setup_counter      : natural range 0 to G_DOUT_SETUP_TIME - 1;          -- counter for busy high time
 
-- ******************* Function that creates samples  ********************* -- 
function mk_sample( chip_id : integer; frame_id : natural; sample_idx : natural)
return std_logic_vector is variable v : unsigned(15 downto 0);
begin
    -- [15:12]=chip_id, [11:8]=frame_id(3:0), [7:0]=sample_idx
    v := (others => '0');
    v(15 downto 12) := to_unsigned(chip_id, 4);
    v(11 downto 8)  := to_unsigned(frame_id, 4);
    v(7 downto 0)   := to_unsigned(sample_idx, 8);
    return std_logic_vector(v);
end function;


begin
    -- **************** Combitatoinal part *********** -- 
    adc_data_bus <= adc_data_bus_r;                -- 1 clk cycle to get updated
    selected <= selected_r; 
    busy <= busy_r;

-- Note: No synchronizers are required here, as this logic is used only for simulation and all models run on the same PC system clock.
    edge_detecor : process(clk)
    begin
        if rising_edge(clk) then 
            if rst_n = '0' then 
                cs_n_d     <= '0';
                rd_n_d     <= '0'; 
                convst_d <= '0';
            else
                cs_n_d     <= cs_n;
                rd_n_d     <= rd_n;
                convst_d <= convst;
            end if;
        end if;
    end process edge_detecor; 

    start_conv : Process (clk)
    begin 
        if rising_edge(clk) then 
            if rst_n = '0' then 
                frame_id <= 0;
                samples <= (others => (others => '0'));
                busy_start <= '0'; 
                busy_r <= '0';
                conversion_time_counter <= 0;
                busy_setup_counter <= 0;
            else
                if convst_d = '0' and convst = '1' then 
                    if busy_r = '0' and busy_start = '0' then
                        busy_start <= '1'; 

                        for sample_idx in 0 to G_NUM_HALFWORDS-1 loop
                            samples(sample_idx) <= mk_sample(G_CHIP_ID, frame_id, sample_idx);
                        end loop; 

                        frame_id <= frame_id + 1;
                    end if;
                
                end if; 
                
                if busy_start = '1' then 
                    if busy_setup_counter >= G_BUSY_SETUP_TIME - 1 then         -- -1 as 1 cycle is consumed already  to set up the flag busy_start.
                        busy_r <= '1';
                        busy_start <= '0';
                        busy_setup_counter <= 0;
                    else 
                        busy_setup_counter <= busy_setup_counter + 1;
                    end if; 
                end if;

                if busy_r = '1' then 
                    if conversion_time_counter >= G_CONV_CYCLES - 1 then 
                        busy_r <= '0'; 
                        conversion_time_counter <= 0;
                    else 
                        conversion_time_counter <= conversion_time_counter + 1 ;
                    end if;
                end if;
            end if;
        end if;
    end process start_conv;


    reading_samples : process(clk) 
    begin 
        if rising_edge(clk) then 
            if rst_n = '0' then 
                dout_setup <= '0';
                send_sample_idx <= 0;
            else
                if cs_n = '0' and rd_n_d = '1' and rd_n = '0' then
                    dout_setup <= '1';
                end if; 

                if dout_setup = '1' then
                    if dout_setup_counter >= G_DOUT_SETUP_TIME - 1 then 
                        adc_data_bus_r <= samples(send_sample_idx); 
                        dout_setup_counter <= 0;
                        dout_setup <= '0';
                        
                        if send_sample_idx >= G_NUM_HALFWORDS - 1 then 
                            send_sample_idx <= 0;
                        else 
                            send_sample_idx <= send_sample_idx + 1;
                        end if;
                        
                    else 
                        dout_setup_counter <= dout_setup_counter + 1;
                    end if;
                end if;
            end if; 
        end if;
    end process reading_samples;


    cs_n_line : process (clk) 
    begin 
        if rising_edge(clk) then 
            if rst_n = '0' then 
                selected_r <= '0';
            else 
                if cs_n_d = '1' and cs_n = '0' then
                    selected_r <= '1';
                elsif cs_n_d = '0' and cs_n = '1' then
                    selected_r <= '0';
                end if;
            end if;
        end if;
    end process cs_n_line;

end architecture  sim;
