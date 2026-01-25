library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_spi_master is
end entity;

architecture sim of tb_spi_master is

    -- Clock period: 100 MHz
    constant CLK_PERIOD : time := 10 ns;

    -- DUT signals
    signal clk    : std_logic := '0';
    signal rst_n        : std_logic := '1';

    signal ena        : std_logic := '0';
    signal write_byte : std_logic_vector(7 downto 0) := (others => '0');
    signal last_byte  : std_logic := '0';

    signal miso_line  : std_logic := '0';
    signal mosi_line  : std_logic;
    signal sclk_line  : std_logic;
    signal cs_n_line  : std_logic;

    signal read_byte  : std_logic_vector(7 downto 0);
    signal done       : std_logic;

    -- Simple SPI slave model (Mode 0: CPOL=0, CPHA=1)
    signal slave_tx_shift_reg    : std_logic_vector(7 downto 0) :=  x"A5";             -- data slave will send
    signal slave_rx_shift_reg    : std_logic_vector(7 downto 0) := (others => '0');              -- what slave received

    signal sent_bit_cnt          : integer range 0 to 8 := 0;
    signal recieved_bit_cnt      : integer range 0 to 8 := 0;

    -- byte after read transactions is done will be copied here
    signal slave_read_byte       : std_logic_vector(7 downto 0) :=  (others => '0');   

    -- byte that the slave wills end. 
    signal slave_write_byte      : std_logic_vector(7 downto 0) := x"A5";

    signal prev_sclk    : std_logic := '0';


begin
    --------------------------------------------------------------------
    -- System clock
    --------------------------------------------------------------------
    clk_gen : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process clk_gen;

    --------------------------------------------------------------------
    -- Reset
    --------------------------------------------------------------------
    rst_gen : process
    begin
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait;
    end process rst_gen;

    --------------------------------------------------------------------
    -- DUT instantiation
    --------------------------------------------------------------------
    uut : entity work.spi_master
        port map (
            clk        => clk,
            rst_n      => rst_n,

            ena        => ena,
            write_byte => write_byte,
            last_byte  => last_byte,

            spi_miso   => miso_line,
            spi_mosi   => mosi_line,
            spi_sclk   => sclk_line,
            spi_cs     => cs_n_line,

            read_byte  => read_byte,
            done       => done
        );



    --------------------------------------------------------------------
    -- SPI SLAVE BEHAVIOUR (for testing)
    -- Assumes SPI mode 0:
    --  - sclk idle low
    --  - data valid on rising edge
    --------------------------------------------------------------------
    slave_model : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then 
                prev_sclk  <= '0';
                sent_bit_cnt <= 0;
                recieved_bit_cnt <= 0;
            else
                prev_sclk <= sclk_line;

                if cs_n_line = '0' then
                    if sent_bit_cnt < 8 then 
                        if prev_sclk = '0' and sclk_line = '1' then                     -- detect rising edge of SCLK from master

                            -- drive MISO with MSB of slave_tx_reg
                            miso_line    <= slave_tx_shift_reg(7);

                            -- shift TX register left
                            slave_tx_shift_reg <= slave_tx_shift_reg(6 downto 0) & '0';
                            sent_bit_cnt <= sent_bit_cnt + 1;
                        end if;
                    else
                        slave_tx_shift_reg <= slave_write_byte;
                        sent_bit_cnt <= 0;
                    end if;

                    if recieved_bit_cnt < 8 then 
                        if prev_sclk = '1' and sclk_line = '0' then   -- falling edge detection 
                            slave_rx_shift_reg <= slave_rx_shift_reg(6 downto 0) & mosi_line;
                            recieved_bit_cnt <= recieved_bit_cnt + 1;
                        end if;
                    else 
                        slave_read_byte <= slave_rx_shift_reg;
                        slave_rx_shift_reg <= (others => '0');
                        recieved_bit_cnt <= 0;
                    end if;
                else
                    -- CS high: reset "transaction-local" state
                    miso_line    <= '0';
                end if;
            end if;
        end if;
    end process;




    
    --------------------------------------------------------------------
    -- Stimulus
    --------------------------------------------------------------------
    stim_proc : process
    begin
        -- wait for reset deassertion
        wait until rst_n = '1';
        wait for 50 ns;

        ----------------------------------------------------------------
        -- 1) First 8-bit transaction
        ----------------------------------------------------------------
        report "TB: Starting first SPI transaction..." severity note;

        slave_write_byte <= x"A5"; -- what the slave send to the master
        write_byte <= x"3C";       -- what master will send on MOSI
        last_byte  <= '0';         -- not the last byte yet

        -- pulse ena for one clock to start
        ena <= '1';
        wait for CLK_PERIOD;
        ena <= '0';

        wait until sent_bit_cnt = 0 or sent_bit_cnt = 8;
        slave_write_byte <= x"5A"; -- what the slave send to the master in the second iteration

        -- wait until master asserts 'done' (one byte finished)
        wait until done = '1';
        wait for CLK_PERIOD;

        report "TB: First transaction finished. Master read = " &
            to_hstring(to_bitvector(read_byte)) severity note;

        -- Check that master received 0xA5
        assert read_byte = x"A5"
            report "ERROR: First transaction, expected 0xA5, got " &
                to_hstring(to_bitvector(read_byte))
            severity error;

        assert slave_read_byte = x"3C"
            report "ERROR: First transaction, expected slave read 0x3C, got " &
                to_hstring(to_bitvector(slave_read_byte))
            severity error;

        ----------------------------------------------------------------
        -- 2) Second 8-bit transaction, with last_byte = '1'
        ----------------------------------------------------------------
        --wait for 200 ns;

        report "TB: Starting second SPI transaction..." severity note;

        write_byte   <= x"F0";
        last_byte    <= '1';       -- mark this as the last byte in frame

        ena <= '1';   -- to restart sclk
        wait for CLK_PERIOD;
        ena <= '0';

        wait until done = '1';
        wait for CLK_PERIOD;


        report "TB: Second transaction finished. Master read = " &
            to_hstring(to_bitvector(read_byte)) severity note;

        assert read_byte = x"5A"
            report "ERROR: Second transaction, expected 0x5A, got " &
                to_hstring(to_bitvector(read_byte))
            severity error;

        assert slave_read_byte = x"F0"
            report "ERROR: Second transaction, expected salve tp read 0xF0, got " &
                to_hstring(to_bitvector(slave_read_byte))
            severity error;
            
        wait until cs_n_line = '1';
        ----------------------------------------------------------------
        report "TB: All SPI tests completed successfully." severity note;
        ----------------------------------------------------------------

        wait;
    end process;

end architecture;
