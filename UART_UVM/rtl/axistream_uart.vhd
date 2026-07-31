-- //////////////////////////////////////////////////////////////////////////////////
-- // Engineer: Abdelrahman Hewala
-- // 
-- // Create Date: 26/07/2026 
-- // Design Name: axistream_uart
-- // Project Name: EKF on FPGA with HLS
-- // Target Devices: Xilinx Basys 3
-- // Tool Versions: 2024.2
-- //
-- // Description: 
-- // this iP is a full custamiszable axi stream Uart module
-- // Revision 0.01 - File Created
-- // Revision 0.02 - Added TX/RX shift engines, AXI-Stream handshake, parity/frame
-- //                  error checking, uart_txd output drive
-- // Additional Comments:
-- //
--
-- //////////////////////////////////////////////////////////////////////////////////
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
entity axistream_uart is
    generic (
        BAUDRATE      : natural   := 115200;         -- Minmum baud rate = 110
        PARITY_BIT    : character := 'N';            -- Types of Parities: N: none, E: Even and O: Odd, any invalid Char will be treated as "none"
        EIGHT_BIT     : boolean   := true;           -- True : Eight bits mode. False: 7 bits mode, any invalid entery will be treated as True: 8 bits
        TWO_STOP_BITS : boolean   := false;           -- False: one Stop bit / True: two Stop bits, invalid input will be treated as False: one stop bit
        OVERSAMPLE    : natural   := 16;             -- RX oversampling factor (ticks per bit)
        CLK_FREQ_HZ   : natural   := 100_000_000    -- system clock frequency
    );
    Port (
        -- Clock and Resets
        clk          : in std_logic;     -- system clk 100 MHz
        rst_n        : in std_logic;
        -- UART interface
        uart_txd    : out std_logic;   -- UART TX port
        uart_rxd    : in std_logic;    -- UART TX port
        -- Input interface / Write
        din         : in  std_logic_vector(7 downto 0);
        din_valid   : in  std_logic;   -- AXI Stream valid input flag
        din_ready   : out std_logic;    -- Axi Stream Ready to take input flag
        -- Output Interface / Read
        dout         : out std_logic_vector(7 downto 0);
        dout_valid   : out std_logic;   -- AXI Stream valid output flag / data valid to read
        dout_ready   : in  std_logic;    -- Axi Stream Ready to take input flag
        frame_error  : out std_logic;   -- when FRAME_ERROR = 1, stop bit was invalid
        parity_error : out std_logic    -- when PARITY_ERROR = 1, parity bit was invalid
    );

end entity;
architecture RTL of axistream_uart is
    -- Constants
    -- Sampling clock generation: fractional NCO (phase accumulator)
    -- ---------------------------------------------------------------
    -- Instead of a fixed integer divisor (which bakes in one rounding error
    -- on every tick), we accumulate a fractional increment each clock and
    -- let baud_tick fire on accumulator overflow. The long-run average tick
    -- rate converges to BAUDRATE*OVERSAMPLE with error bounded by 1/2^ACC_WIDTH,
    -- Desired Period -> 2^24. then System period -> step? . it is a ratio question.
    -- Solve it and convert to the Freq domain. u will get the same final eq. of the Step
    -- resulting integer constant is synthesized, no real-valued hardware.
    constant  NCO_ACC_WIDTH     : natural := 24;                    --  Numerically Controlled Oscillator resolution
    constant  NCO_STEP : natural := natural(round((real(BAUDRATE) * real(OVERSAMPLE) / real(CLK_FREQ_HZ)) * (2.0 ** NCO_ACC_WIDTH)));

    -- UART RX Cross Domain Sync flipflops
    signal uart_rx_sync_ff1 : std_logic := '0';
    signal uart_rx_sync_ff2 : std_logic := '0';
    -- Frame geometry Signals
    signal parity_bits  : natural range 0 to 1 := 0;
    signal stop_bits    : natural range 1 to 2 := 1;
    signal payload_bits : integer range 7 to 8 := 8;
    signal frame_bits   : natural range 0 to 12 := 10;
    signal nco_acc           : unsigned(NCO_ACC_WIDTH - 1 downto 0) := (others => '0');   -- one extra bit to catch the overflow
    signal baud_tick         : std_logic := '0';    -- pulses once every OVERSAMPLE-th tick period

    -- TX engine
    type tx_state_t is (TX_IDLE, TX_START, TX_DATA, TX_PARITY, TX_STOP);
    signal tx_state    : tx_state_t := TX_IDLE;
    signal tx_shift    : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_idx  : natural range 0 to 7 := 0;
    signal tx_stop_idx : natural range 0 to 1 := 0;
    signal tx_os_cnt   : natural range 0 to OVERSAMPLE-1 := 0;
    signal tx_line     : std_logic := '1';

    -- RX engine
    type rx_state_t is (RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP, RX_OUT);
    signal rx_state        : rx_state_t := RX_IDLE;
    signal rx_shift        : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_bit_idx      : natural range 0 to 7 := 0;
    signal rx_stop_idx     : natural range 0 to 1 := 0;
    signal rx_os_cnt       : natural range 0 to OVERSAMPLE-1 := 0;
    signal dout_i          : std_logic_vector(7 downto 0) := (others => '0');
    signal dout_valid_i    : std_logic := '0';
    signal rx_frame_err_i  : std_logic := '0';
    signal rx_parity_err_i : std_logic := '0';

    -- simple XOR-tree parity, avoids depending on VHDL-2008 xor_reduce
    function calc_parity(v : std_logic_vector) return std_logic is
        variable p : std_logic := '0';
    begin
        for i in v'range loop
            p := p xor v(i);
        end loop;
        return p;
    end function;
--=================================================================--
begin
    -- Frame geometry: concurrent (combinational) signal assignments
    parity_bits  <= 1 when (PARITY_BIT = 'O' or PARITY_BIT = 'E') else 0;
    payload_bits <= 8 when EIGHT_BIT else 7;
    stop_bits    <= 2 when TWO_STOP_BITS else 1;

    -- Start bit (1) + payload + parity (0 or 1) + stop bits
    frame_bits   <= 1 + payload_bits + parity_bits + stop_bits;

    nco_tick_gen_p : process(clk)
        variable sum : unsigned(NCO_ACC_WIDTH downto 0);   -- one extra bit catches the carry/overflow
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                nco_acc   <= (others => '0');
                baud_tick <= '0';
            else
                sum       := ('0' & nco_acc) + to_unsigned(NCO_STEP, NCO_ACC_WIDTH + 1);
                nco_acc   <= sum(NCO_ACC_WIDTH - 1 downto 0);
                baud_tick <= sum(NCO_ACC_WIDTH);   -- carry-out bit = overflow = tick pulse
            end if;
        end if;
    end process nco_tick_gen_p;
     uart_rx_synchronizer_p : process(clk) is
     begin
        if rising_edge(clk) then
            if rst_n = '0' then
                uart_rx_sync_ff1 <= '0';
                uart_rx_sync_ff2 <= '0';
            else
                uart_rx_sync_ff1 <= UART_RXD;
                uart_rx_sync_ff2 <= uart_rx_sync_ff1;
            end if;
        end if;
     end process uart_rx_synchronizer_p;

    -- ---------------------------------------------------------------
    -- TX engine: AXI-Stream input (din/din_valid/din_ready) -> serial line
    -- din_ready is high only while idle; a transfer happens on the cycle
    -- both din_valid and din_ready are high (standard AXI-Stream handshake).
    -- ---------------------------------------------------------------
    din_ready <= '1' when tx_state = TX_IDLE else '0';
    uart_txd  <= tx_line;

    tx_engine_p : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                tx_state    <= TX_IDLE;
                tx_line     <= '1';
                tx_os_cnt   <= 0;
                tx_bit_idx  <= 0;
                tx_stop_idx <= 0;
                tx_shift    <= (others => '0');
            else
                case tx_state is

                    when TX_IDLE =>
                        tx_line <= '1';
                        if din_valid = '1' then
                            tx_shift  <= din;
                            tx_os_cnt <= 0;
                            tx_state  <= TX_START;
                        end if;

                    when TX_START =>
                        tx_line <= '0';
                        if baud_tick = '1' then
                            if tx_os_cnt = OVERSAMPLE-1 then
                                tx_os_cnt  <= 0;
                                tx_bit_idx <= 0;
                                tx_state   <= TX_DATA;
                            else
                                tx_os_cnt <= tx_os_cnt + 1;
                            end if;
                        end if;

                    when TX_DATA =>
                        tx_line <= tx_shift(tx_bit_idx);
                        if baud_tick = '1' then
                            if tx_os_cnt = OVERSAMPLE-1 then
                                tx_os_cnt <= 0;
                                if tx_bit_idx = payload_bits-1 then
                                    if parity_bits = 1 then
                                        tx_state <= TX_PARITY;
                                    else
                                        tx_stop_idx <= 0;
                                        tx_state    <= TX_STOP;
                                    end if;
                                else
                                    tx_bit_idx <= tx_bit_idx + 1;
                                end if;
                            else
                                tx_os_cnt <= tx_os_cnt + 1;
                            end if;
                        end if;

                    when TX_PARITY =>
                        if PARITY_BIT = 'O' then
                            tx_line <= not calc_parity(tx_shift(payload_bits-1 downto 0));
                        else
                            tx_line <= calc_parity(tx_shift(payload_bits-1 downto 0));
                        end if;
                        if baud_tick = '1' then
                            if tx_os_cnt = OVERSAMPLE-1 then
                                tx_os_cnt   <= 0;
                                tx_stop_idx <= 0;
                                tx_state    <= TX_STOP;
                            else
                                tx_os_cnt <= tx_os_cnt + 1;
                            end if;
                        end if;

                    when TX_STOP =>
                        tx_line <= '1';
                        if baud_tick = '1' then
                            if tx_os_cnt = OVERSAMPLE-1 then
                                tx_os_cnt <= 0;
                                if tx_stop_idx = stop_bits-1 then
                                    tx_state <= TX_IDLE;
                                else
                                    tx_stop_idx <= tx_stop_idx + 1;
                                end if;
                            else
                                tx_os_cnt <= tx_os_cnt + 1;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process tx_engine_p;

    -- ---------------------------------------------------------------
    -- RX engine: serial line -> AXI-Stream output (dout/dout_valid/dout_ready)
    -- Start bit is confirmed by resampling at mid-bit to reject glitches.
    -- dout_valid holds high (data held stable) until dout_ready is seen,
    -- i.e. the consumer must accept before the next frame can be received --
    -- there is no elastic buffering here, by design, to keep this small.
    -- ---------------------------------------------------------------
    dout         <= dout_i;
    dout_valid   <= dout_valid_i;
    frame_error  <= rx_frame_err_i;
    parity_error <= rx_parity_err_i;

    rx_engine_p : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                rx_state        <= RX_IDLE;
                rx_os_cnt       <= 0;
                rx_bit_idx      <= 0;
                rx_stop_idx     <= 0;
                rx_shift        <= (others => '0');
                dout_i          <= (others => '0');
                dout_valid_i    <= '0';
                rx_frame_err_i  <= '0';
                rx_parity_err_i <= '0';
            else
                case rx_state is

                    when RX_IDLE =>
                        if uart_rx_sync_ff2 = '0' then     -- candidate start bit
                            rx_os_cnt <= 0;
                            rx_state  <= RX_START;
                        end if;

                    when RX_START =>
                        if baud_tick = '1' then
                            if rx_os_cnt = (OVERSAMPLE/2)-1 then   -- mid-bit resample
                                if uart_rx_sync_ff2 = '0' then
                                    rx_os_cnt  <= 0;
                                    rx_bit_idx <= 0;
                                    rx_shift   <= (others => '0');
                                    rx_state   <= RX_DATA;
                                else
                                    rx_state <= RX_IDLE;           -- false start / glitch
                                end if;
                            else
                                rx_os_cnt <= rx_os_cnt + 1;
                            end if;
                        end if;

                    when RX_DATA =>
                        if baud_tick = '1' then
                            if rx_os_cnt = OVERSAMPLE-1 then
                                rx_os_cnt             <= 0;
                                rx_shift(rx_bit_idx)  <= uart_rx_sync_ff2;
                                if rx_bit_idx = payload_bits-1 then
                                    if parity_bits = 1 then
                                        rx_state <= RX_PARITY;
                                    else
                                        rx_stop_idx <= 0;
                                        rx_state    <= RX_STOP;
                                    end if;
                                else
                                    rx_bit_idx <= rx_bit_idx + 1;
                                end if;
                            else
                                rx_os_cnt <= rx_os_cnt + 1;
                            end if;
                        end if;

                    when RX_PARITY =>
                        if baud_tick = '1' then
                            if rx_os_cnt = OVERSAMPLE-1 then
                                rx_os_cnt <= 0;
                                if PARITY_BIT = 'O' then
                                    rx_parity_err_i <= uart_rx_sync_ff2 xor (not calc_parity(rx_shift(payload_bits-1 downto 0)));
                                else
                                    rx_parity_err_i <= uart_rx_sync_ff2 xor calc_parity(rx_shift(payload_bits-1 downto 0));
                                end if;
                                rx_stop_idx <= 0;
                                rx_state    <= RX_STOP;
                            else
                                rx_os_cnt <= rx_os_cnt + 1;
                            end if;
                        end if;

                    when RX_STOP =>
                        if baud_tick = '1' then
                            if rx_os_cnt = OVERSAMPLE-1 then
                                rx_os_cnt <= 0;
                                if uart_rx_sync_ff2 = '0' then
                                    rx_frame_err_i <= '1';
                                end if;
                                if rx_stop_idx = stop_bits-1 then
                                    dout_i       <= rx_shift;
                                    dout_valid_i <= '1';
                                    rx_state     <= RX_OUT;
                                else
                                    rx_stop_idx <= rx_stop_idx + 1;
                                end if;
                            else
                                rx_os_cnt <= rx_os_cnt + 1;
                            end if;
                        end if;

                    when RX_OUT =>
                        if dout_ready = '1' then
                            dout_valid_i    <= '0';
                            rx_frame_err_i  <= '0';
                            rx_parity_err_i <= '0';
                            rx_state        <= RX_IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process rx_engine_p;

end architecture RTL;