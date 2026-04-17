-- LTC2308_ctrl.vhd
--
-- This module implements an SPI controller customized for an LTC2308
-- Analog-to-Digital Converter (ADC).
--
-- Generics:
--   CLK_DIV : Divides the main clock to generate the SCLK frequency.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LTC2308_ctrl is
	generic (
		CLK_DIV : integer := 1
	);
	port (
		clk      : in  std_logic;
		nrst     : in  std_logic;
		start    : in  std_logic;
		cfg      : in  std_logic_vector(5 downto 0);
		rx_data  : out std_logic_vector(11 downto 0);
		busy     : out std_logic;

		sclk     : out std_logic;
		conv     : out std_logic;
		mosi     : out std_logic;
		miso     : in  std_logic
	);
end entity LTC2308_ctrl;

architecture internals of LTC2308_ctrl is

	type state_type is (IDLE, CONV_PULSE, CONV_WAIT, TRANSFER, HOLD);
	signal state : state_type;

	signal clk_cnt   : integer range 0 to CLK_DIV;
	signal sclk_int  : std_logic;
	signal sclk_rise : std_logic;
	signal sclk_fall : std_logic;

	signal bit_cnt   : integer range 0 to 12;
	signal wait_cnt  : integer range 0 to 200;

	signal tx_reg    : std_logic_vector(11 downto 0);
	signal rx_reg    : std_logic_vector(11 downto 0);

begin

	sclk <= sclk_int;

	process(clk, nrst)
	begin
		if nrst = '0' then
			state    <= IDLE;
			bit_cnt  <= 0;
			wait_cnt <= 0;
			conv     <= '0';
			busy     <= '0';
		elsif rising_edge(clk) then
			case state is
				when IDLE =>
					conv <= '0';
					busy <= '0';
					if start = '1' then
						state   <= CONV_PULSE;
						conv    <= '1';
						busy    <= '1';
					end if;

				when CONV_PULSE =>
					conv     <= '0';
					wait_cnt <= 40;
					state    <= CONV_WAIT;

				when CONV_WAIT =>
					if wait_cnt = 0 then
						state   <= TRANSFER;
						bit_cnt <= 12 - 1;
					else
						wait_cnt <= wait_cnt - 1;
					end if;

				when TRANSFER =>
					if sclk_rise = '1' then
						bit_cnt <= bit_cnt - 1;
						if bit_cnt = 0 then
							state <= HOLD;
						end if;
					end if;

				when HOLD =>
					conv <= '0';
					busy <= '0';
					if start = '0' then
						state   <= IDLE;
					end if;

			end case;
		end if;
	end process;

	process(clk, nrst)
	begin
		if nrst = '0' then
			clk_cnt   <= 0;
			sclk_int  <= '0';
			sclk_rise <= '0';
			sclk_fall <= '0';
		elsif rising_edge(clk) then
			sclk_rise <= '0';
			sclk_fall <= '0';

			if state = TRANSFER then
				clk_cnt <= clk_cnt + 1;
				if clk_cnt = CLK_DIV - 1 then
					clk_cnt <= 0;

					sclk_int <= not sclk_int;
					if sclk_int = '0' then
						sclk_rise <= '1';
					else
						sclk_fall <= '1';
					end if;
				end if;
			else
				clk_cnt  <= 0;
				sclk_int <= '0';
			end if;
		end if;
	end process;

	process(clk, nrst)
	begin
		if nrst = '0' then
			tx_reg  <= (others => '0');
			rx_reg  <= (others => '0');
			rx_data <= (others => '0');
			mosi    <= '0';
		elsif rising_edge(clk) then

			if state = IDLE then
				if start = '1' then
					tx_reg <= cfg & "000000";
					mosi   <= cfg(5);
				end if;

			elsif state = TRANSFER then
				if sclk_rise = '1' then
					rx_reg <= rx_reg(10 downto 0) & miso;
				end if;

				if sclk_fall = '1' then
					tx_reg <= tx_reg(10 downto 0) & '0';
					mosi   <= tx_reg(10);
				end if;

			elsif state = HOLD then
				if sclk_fall = '1' then
					rx_data <= rx_reg;
				end if;
			end if;

		end if;
	end process;

end architecture internals;
