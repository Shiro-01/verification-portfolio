library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_fifo is
    generic (
        G_DEPTH : positive := 16
    );
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        -- Slave Interface (Write)
        s_axis_tdata  : in  std_logic_vector(31 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        -- Master Interface (Read)
        m_axis_tdata  : out std_logic_vector(31 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic
    );
end entity;

architecture rtl of axis_fifo is
    type fifo_mem is array (0 to G_DEPTH-1) of std_logic_vector(31 downto 0);
    signal mem : fifo_mem := (others => (others => '0'));
    
    signal wr_ptr, rd_ptr : natural range 0 to G_DEPTH-1 := 0;
    signal count : natural range 0 to G_DEPTH := 0;
    
    signal full, empty : std_logic;
begin
    full  <= '1' when count = G_DEPTH else '0';
    empty <= '1' when count = 0 else '0';

    s_axis_tready <= not full;
    m_axis_tvalid <= not empty;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                wr_ptr <= 0;
                rd_ptr <= 0;
                count  <= 0;
            else
                -- Write Logic
                if (s_axis_tvalid = '1' and not full = '1') then
                    mem(wr_ptr) <= s_axis_tdata;
                    wr_ptr <= (wr_ptr + 1) mod G_DEPTH;
                end if;
                
                -- Read Logic
                if (m_axis_tready = '1' and not empty = '1') then
                    rd_ptr <= (rd_ptr + 1) mod G_DEPTH;
                end if;

                -- Counter Logic
                if (s_axis_tvalid = '1' and not full = '1') and not (m_axis_tready = '1' and not empty = '1') then
                    count <= count + 1;
                elsif not (s_axis_tvalid = '1' and not full = '1') and (m_axis_tready = '1' and not empty = '1') then
                    count <= count - 1;
                end if;
            end if;
        end if;
    end process;
    
    m_axis_tdata <= mem(rd_ptr);
end architecture;