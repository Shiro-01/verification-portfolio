-- SPI master RTL
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_master is
    -- Generic parameters
    generic(
        clk_div : unsigned(15 downto 0) -- clock divider for SPI clock, if the system clk is 100Mhz. and the desired spi_sclk is 25 MHz, then this value shall be (4) -- note the implemnation later requires double of the devisor 
    );

    port(
        -- control signals ports
        clk : in std_logic;    -- system input clk
        rst_n : in std_logic;
        ena : in std_logic;    -- this signal is a flag comes from the controler to tell the master that a new write transaction is here

        -- PS/Controller interface ( Data comunicatoin signals)
        write_byte: in std_logic_vector(7 downto 0);         -- input byte (from PS or any control device), that we are interested in writing to the spi slave through MOSI
        last_byte: in std_logic;                             -- this is a flag setted by the controller says “After this byte completes, end the transaction (deassert CS).”
        read_byte: out std_logic_vector(7 downto 0);         -- output byte, that we read from the SPI slave via MISO line, and we are returning it back to the controller
        done: out std_logic;                                 -- this is a flag raised  by the SPI master here to tell the controller that we are done “This byte just finished shifting; recieved data is valid now, ready to read.”
    
        -- SPI Interface
        spi_sclk : out std_logic;                                -- SPI clock line
        spi_cs : out std_logic;                                  -- chip select line
        spi_mosi : out std_logic;                                -- Master out slave in spi  line
        spi_miso : in std_logic                                 -- MAster in salve out spi line
    );

end spi_master;


architecture rtl of spi_master is 

    -- signals used in  spi_sclk_gen_p process
    signal clk_div2 : unsigned(16 downto 0);                  -- this register will hold the double value of clock divisor (clk_div). we need double value to be used as a counter to drive 50% duty cycle
    signal data_clk : std_logic;                              -- Data clk, is used internaly to sample/ when to (raed/write) the data bits
    signal running : std_logic;                               -- Flag that we are already dealing with a byte
    signal count : unsigned(32 downto 0);                      -- counter to generate SPI clock (sclk)

    -- signals used in the running process
    signal ena_dly : std_logic;                               -- this refister stores the last enable signal (ena) till the right time to set the runnig flag kicks in (on the next spi_sclk rising edge). if another pulse came in while it is still high or already low but in running state; it will be ignored
    signal bit_count : unsigned(3 downto 0);                   -- this register counts how many bits are written so far

    -- Shift registers that is used in the two processes of reading and writing
    signal reg_shift_out : std_logic_vector(8 downto 0);  -- register that holds the data we want to write to the salve. this register keep shifting bit by bit till the whole byte is writen 
    signal reg_shift_in : std_logic_vector(7 downto 0);   -- register that holds the data we read from the spi salve, it keeps attaching the bits till we have a whole byte

    signal data_clk_dly : std_logic; -- thsi signal is used to detect the rsing edge of the data sampling clock
begin
    -- computationl and constant signal represents the MAX value of the count. it is doubling the clk divisor
    clk_div2 <= clk_div & '0';  
    
    
    -- counter process used to generate SPI clock spi_sclk
    clk_Counter_p : process(clk) is
    begin
        if rising_edge(clk) then
            if(rst_n = '0') then
                count <= (others => '0');
            elsif (count = clk_div2 - 1) then
                count <= (others => '0');
            else
                count <= count + 1;
            end if;
        end if;
    end process clk_counter_p;



    -- spi clock  (spi_sclk) & data clock generation process.
    -- requirement: drive them only in case we are in the running state (cs is down) ELSE, stay at the idel condition 
    -- the sclk is configured to be  CPOL = 0, active high, idel is low
    -- data_clk: is config to be CPHA = 1, Meaning reading on the trailing edge, and in case of CPOL = 0, it is the falling edge.
    -- To sum up,  CPOL = 0, CPHA = 1, then data_clk is high when spi_sclk is low, and data_clk is high when spi_sclk is low
    -- note: later the (sent /recieved) bits are seted on the rising edge of the SPI_CLK, and sampling them at data_clk, allows us to read in the midle of the cycle
    clk_gen_p : process(clk) is
    begin
        if rising_edge(clk) then
            if(rst_n ='0')  then-- active low rest
                spi_sclk <= '0';
            else
                if(running = '1' and bit_count < 8) then -- Shiro: this to elimiate the clk imeditly after the 8th bite (8th cycle) is set.

                    if(count < clk_div) then
                        spi_sclk <= '1';
                        data_clk <= '0';

                    elsif(count >= clk_div) then
                        spi_sclk <= '0';
                        data_clk <= '1';
                    end if;

                else  -- if we are not in the running state, then keep signals idel
                    spi_sclk <= '0';  
                    data_clk <= '0';
                end if;

            end if;
        end if;
    end process clk_gen_p;

    -- bit count counter process used to count 8 bits since running flage went high. then reset to zero
    bit_count_counter_p : process(clk) is 
    begin 
        if rising_edge(clk) then
            if rst_n = '0' then
                bit_count <= (others => '0');
            else 
                -- once we are running, start couting. note with current configration, bit_count get updated only at the next rising edge when the first bit is already writen. meaing we have a lag by 1 bit
                -- so, once the counter value  gets to 8, then it means we finsihed already writing the 8th bits, and we can reset the counter (reason behind that, is the reading flag high gets effective only in the next cycle it is written at, and this where count is alredy 0, so we missed already the first rising edge)
                if(running = '1' and count =  clk_div2 - 1) then
                    if bit_count < 8 then
                        bit_count <= bit_count + 1;
                    else
                        bit_count <= (others => '0');
                    end if;

                elsif (bit_count = 8) then
                    bit_count <=  (others => '0');

                end if;
            end if;
        end if;
    end process bit_count_counter_p;

    -- Running process, is the process resposible of setting the running internal flag depending on the enable pulse (ena) from the controller and the bit counter to set it back to 0
    -- so running stays high for 8 bits => full 8 spi_sclk cycles + 1 clk
    running_p : process(clk) is 
    begin 
        if rising_edge(clk) then
            if (rst_n = '0') then
                ena_dly <= '0';
                running <= (others => '0');
                
            else
            -- capture the pulse ena only if we are NOT in the running state, else it stays low.
                if running = '1' then
                    ena_dly <= '0';
                elsif ena = '1' then
                    ena_dly <= '1';
                end if;
                -- when ena_dly gets effective( becaomes high), and the counter count, controls spi_sclk, equals its last value (clk_div2 - 1). only then set the running flag to high. 
                -- Q) why not at count = 0? cause  (clk_div2 - 1) is the last count after words we go directly to zero, and we need time for that update. so this to ensure spi_clk happen on count = 0
                if(ena_dly = '1' and count = (clk_div2 - 1)) then
                    running <= '1';
                -- once the bit counter is 8, this means the 8th bit is already finsihed writting and we can pull the running flag down. 
                -- Note: we have a small latancy of 1 clk cycle for the flag to get updated to 0, but it is tolarated! as the spi_sclk will go to zero in the next cycle but that's fine
                elsif ( bit_count  = 8) then
                    running <= '0';   
                end if;

            end if;
        end if;
    end process running_p;

    -- CS process,  resposible of pull cs line low (our Configuíration is active low), and release it once we get the last_byte flag's process done!
    spi_cs_p : process(clk) is 
    begin 
        if rising_edge(clk) then
            if rst_n = '0' then
                spi_cs <= '1';
            else
                -- last byte is being kept high by the controller till he recieves the done signal (which equals Not running) form the spi master. only then he release the last_byte flag. the controller also will be keeping ena low, and no ena stored and ena_dly. 
                if running = '0' and ena = '0' and ena_dly = '0' and last_byte = '1' then   --also no need for the bit count check = 0, as the running flag gets updated  to  0 on the same trigger bit count = 8
                    spi_cs <= '1';  
                    
                elsif  ena = '1' then
                    spi_cs <= '0';  
                end if;
            end if;

        end if;

    end process spi_cs_p;

    -- process of writting the data out to the SPI slave peripheral 
    data_out_p : process(clk) is
    begin 
        if rising_edge(clk) then
            if rst_n = '0' then
                reg_shift_out <= (others => '0');
            else
                -- as spi, is synchronos we prepare the write byte and save it in the shift register already on the en signal, then we have the 8 spi_sclk cycles to write 
                if ena = '1' then
                    reg_shift_out <= '0' & write_byte; -- by this nothing has been wrien yet, the lise is zero
                elsif running = '1' and count = 0 and bit_count < 8 then  -- running flag gets actually ipdated extactly at the time when u read count ? 0, we using count = 0, to mark the rising edge
                    reg_shift_out <= reg_shift_out(7 downto 0 ) & '0'; -- we start shifting and send the first MSB
                end if;
            end if;
        end if;
    end process data_out_p ;

    data_in_P : process(clk) is
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                reg_shift_in <= (others => '0');
                data_clk_dly <= '0';
            else
                data_clk_dly <= data_clk;
                if(ena = '1') then  -- clean the inreg_shift_input register
                    reg_shift_in <= (others => '0');
                else
                    if(running = '1' and data_clk_dly = '0' and data_clk = '1') then   -- the time data_clk goes up is exactly at  'count = clk_div', but let's stick to the book design
                        reg_shift_in <= reg_shift_in(6 downto 0) and spi_miso;         -- we can literlay cancel data clk as we alredy that we are sampling on the faling edge of sclk or rising of the imaginary data_clk
                    end if;
                end if;
            end if;
        end if;
    end process data_in_p;

    read_byte <= reg_shift_in; -- controller doesn'T read until done flag is rasied AKA, state is not running any more
    spi_mosi <= reg_shift_out(8);
    done <= not running;

end architecture rtl; 
