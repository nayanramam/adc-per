LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;

ENTITY ADC IS
	PORT (
        -- System signals
		clk    : IN STD_LOGIC;
		resetn : IN STD_LOGIC;
		io_read : IN STD_LOGIC;

        -- WRITE TO SCOMP
		sel	 : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        config  : IN STD_LOGIC_VECTOR(15 DOWNTO 0);

		-- READ TO SCOMP
        adc_data  : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);

		-- SPI to LTC2308 chip
		sclk : OUT STD_LOGIC;
		conv : OUT STD_LOGIC;
		mosi : OUT STD_LOGIC;
		miso : IN  STD_LOGIC

	);
END ADC;

ARCHITECTURE arch OF ADC IS
	-- SCOMP Communication Enum Types
	TYPE MODE_TYPE IS ( sgl_end, diff, ttl_debug, err );
	TYPE CHANNEL_TYPE IS ( ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7, ch_error);
	TYPE TTL_CONFIG IS ( ttl_input_0, ttl_input_1, ttl_output_0, ttl_output_1 );
	
	-- SCOMP Communication Signals	
	SIGNAL channel  : CHANNEL_TYPE;
	SIGNAL channel_neg : CHANNEL_TYPE;
	SIGNAL io_mode  : MODE_TYPE;
	SIGNAL ttl_config  : TTL_CONFIG;
	
	-- FSM for free-running conversions
	TYPE ADC_STATE IS (IDLE, CONVERTING, WAIT_DONE, DONE);
	SIGNAL state      : ADC_STATE;
	SIGNAL result_reg : STD_LOGIC_VECTOR(11 DOWNTO 0);

	-- ADC Info Signals
	SIGNAL adc_busy   : STD_LOGIC;
	SIGNAL adc_start  : STD_LOGIC;
	SIGNAL adc_result : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL cfg_word   : STD_LOGIC_VECTOR(5 DOWNTO 0);

BEGIN

	-- Instantiate the LTC2308 controller
	ltc : ENTITY work.LTC2308_ctrl
    
	-- SPI Clock set to 20 MHz
	GENERIC MAP (
        CLK_DIV => 1
    )

	-- Port mapping for the LTC2308 controller
    PORT MAP (
        clk     => clk,
        nrst    => resetn,
        start   => adc_start,
        cfg     => cfg_word,
        rx_data => adc_result,
        busy    => adc_busy,
        sclk    => sclk,
        conv    => conv,
        mosi    => mosi,
        miso    => miso
    );

	-- Build 6-bit LTC2308 config word: S/D | O/S | S1 | S0 | UNI | SLP
	-- Single-ended unipolar mode, channel from Table 1 of datasheet
	WITH channel SELECT
		cfg_word <= "100010" WHEN ch0,
		            "100110" WHEN ch1,
		            "101010" WHEN ch2,
		            "101110" WHEN ch3,
		            "110010" WHEN ch4,
		            "110110" WHEN ch5,
		            "111010" WHEN ch6,
		            "111110" WHEN ch7,
		            "000000" WHEN OTHERS;

	-- Combinationally select channel based on sel
	WITH sel(3 DOWNTO 0) SELECT
		channel <= ch0 WHEN "0000",
		           ch1 WHEN "0001",
		           ch2 WHEN "0010",
		           ch3 WHEN "0011",
		           ch4 WHEN "0100",
		           ch5 WHEN "0101",
		           ch6 WHEN "0110",
		           ch7 WHEN "0111",
		           ch_error WHEN OTHERS;

	-- Combinationally select mode based on sel			   
	WITH sel(5 DOWNTO 4) SELECT
		io_mode <=  sgl_end    WHEN "00",
					diff       WHEN "01",
		            ttl_debug  WHEN "10",
		            err    WHEN OTHERS;

	-- Combinationally select negative channel based on config			   
	WITH config(3 DOWNTO 0) SELECT
		channel_neg <= ch0 WHEN "0000",
				ch1 WHEN "0001",
				ch2 WHEN "0010",
				ch3 WHEN "0011",
				ch4 WHEN "0100",
				ch5 WHEN "0101",
				ch6 WHEN "0110",
				ch7 WHEN "0111",
				ch_error WHEN OTHERS;

	-- Combinationally ttl configuration based on config			   
	WITH config(5 DOWNTO 4) SELECT
		ttl_config <=   ttl_input_0   WHEN "00",
					ttl_output_0       WHEN "01",
		            ttl_input_1  WHEN "10",
		            ttl_output_1    WHEN "11";

	
	--zero-pad in single-ended mode, sign-extend otherwise
	adc_data <= X"DEAD" WHEN (channel = ch_error OR io_mode = err OR channel_neg = ch_error) ELSE
	            "0000" & result_reg WHEN io_mode = sgl_end ELSE
	            (15 DOWNTO 12 => result_reg(11)) & result_reg;

	-- Free-running ADC conversion state machine
	PROCESS (clk, resetn)
	BEGIN
		IF resetn = '0' THEN
			state     <= IDLE;
			adc_start <= '0';
			result_reg <= (OTHERS => '0');

		ELSIF rising_edge(clk) THEN
			CASE state IS

				WHEN IDLE =>
					adc_start <= '1';
					state     <= CONVERTING;

				WHEN CONVERTING =>
					adc_start <= '0';
					IF adc_busy = '1' THEN
						state <= WAIT_DONE;
					END IF;

				WHEN WAIT_DONE =>
					IF adc_busy = '0' THEN
						state <= DONE;
					END IF;

				WHEN DONE =>
					result_reg <= adc_result;
					state      <= IDLE;

			END CASE;
		END IF;
	END PROCESS;
	
END arch;
