-- ---------------------------------------------------------------------------
-- axistream_uart_wrapper.vhd
--
-- Cross-language generic passing (SV parameter -> VHDL 'character' generic)
-- is tool-inconsistent for enumerated/character types, so instead of
-- fighting that at the SV instantiation, this wrapper fixes the generics in
-- pure VHDL. tb_top.sv instantiates this wrapper as a plain, generic-free
-- module. Keep these values in sync with the localparams at the top of
-- uart_uvm_pkg.sv.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity axistream_uart_wrapper is
    port (
        clk          : in  std_logic;
        rst_n        : in  std_logic;
        uart_txd     : out std_logic;
        uart_rxd     : in  std_logic;
        din          : in  std_logic_vector(7 downto 0);
        din_valid    : in  std_logic;
        din_ready    : out std_logic;
        dout         : out std_logic_vector(7 downto 0);
        dout_valid   : out std_logic;
        dout_ready   : in  std_logic;
        frame_error  : out std_logic;
        parity_error : out std_logic
    );
end entity;

architecture STRUCT of axistream_uart_wrapper is
begin
    dut_i : entity work.axistream_uart
        generic map (
            BAUDRATE      => 115200,   -- keep in sync with uart_uvm_pkg::BAUDRATE
            PARITY_BIT    => 'E',      -- keep in sync with uart_uvm_pkg::PARITY_MODE
            EIGHT_BIT     => true,     -- keep in sync with uart_uvm_pkg::EIGHT_BIT
            TWO_STOP_BITS => false,    -- keep in sync with uart_uvm_pkg::TWO_STOP_BITS
            OVERSAMPLE    => 16,
            CLK_FREQ_HZ   => 100_000_000
        )
        port map (
            clk          => clk,
            rst_n        => rst_n,
            uart_txd     => uart_txd,
            uart_rxd     => uart_rxd,
            din          => din,
            din_valid    => din_valid,
            din_ready    => din_ready,
            dout         => dout,
            dout_valid   => dout_valid,
            dout_ready   => dout_ready,
            frame_error  => frame_error,
            parity_error => parity_error
        );
end architecture;
