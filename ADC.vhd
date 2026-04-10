LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.NUMERIC_STD.all;

ENTITY ADC IS
	PORT (
        -- SYSTEM SIGNALS
		clk    : IN STD_LOGIC;
		resetn : IN STD_LOGIC;
		io_read : IN STD_LOGIC;

        -- WRITE TO SCOMP
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
	TYPE FLAG_TYPE IS ( o_ready, i_ready );
	
	-- SCOMP Communication Signals	
	SIGNAL channel  : CHANNEL_TYPE;
	SIGNAL channel_neg : CHANNEL_TYPE;
	SIGNAL io_mode  : MODE_TYPE;
	SIGNAL ttl_config  : TTL_CONFIG;
	SIGNAL flag    : FLAG_TYPE;
	
	-- FSM for free-running conversions
	TYPE ADC_STATE IS (IDLE, CONVERTING, WAIT_DONE, DONE);
	TYPE PHASE_TYPE IS (POS, NEG);
	SIGNAL state      : ADC_STATE;
	SIGNAL phase      : PHASE_TYPE; -- for differential (keeps track of which sample is which)
	SIGNAL result_reg : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL result_pos : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL active_ch  : CHANNEL_TYPE;

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

	-- Choose configuration word to send to ADC based on active_channel
	WITH active_ch SELECT
		cfg_word <= "100010" WHEN ch0,
		            "100110" WHEN ch1,
		            "101010" WHEN ch2,
		            "101110" WHEN ch3,
		            "110010" WHEN ch4,
		            "110110" WHEN ch5,
		            "111010" WHEN ch6,
		            "111110" WHEN ch7,
		            "000000" WHEN OTHERS;

	-- Combinationally select channel based on config
	WITH config(4 DOWNTO 2) SELECT
		channel <= ch0 WHEN "000",
		           ch1 WHEN "001",
		           ch2 WHEN "010",
		           ch3 WHEN "011",
		           ch4 WHEN "100",
		           ch5 WHEN "101",
		           ch6 WHEN "110",
		           ch7 WHEN "111",
		           ch_error WHEN OTHERS;

	-- Combinationally select mode based on config			   
	WITH config(1 DOWNTO 0) SELECT
		io_mode <=  sgl_end    WHEN "00",
					diff       WHEN "01",
		            ttl_debug  WHEN "10",
		            err    WHEN OTHERS;

	-- Combinationally select negative channel based on config			   
	WITH config(7 DOWNTO 5) SELECT
		channel_neg <= ch0 WHEN "000",
				ch1 WHEN "001",
				ch2 WHEN "010",
				ch3 WHEN "011",
				ch4 WHEN "100",
				ch5 WHEN "101",
				ch6 WHEN "110",
				ch7 WHEN "111",
				ch_error WHEN OTHERS;

	-- Combinationally ttl configuration based on config			   
	WITH config(9 DOWNTO 8) SELECT
		ttl_config <=   ttl_input_0   WHEN "00",
					ttl_output_0       WHEN "01",
		            ttl_input_1  WHEN "10",
		            ttl_output_1    WHEN "11";

					
	-- In diff mode, sample channel_neg on the NEG phase; otherwise always sample channel
	active_ch <= channel_neg WHEN (io_mode = diff AND phase = NEG) ELSE channel;

	--zero-pad in single-ended mode, sign-extend otherwise, also check for errors
	adc_data <= X"DEAD" WHEN (channel = ch_error OR io_mode = err OR channel_neg = ch_error) ELSE
	            "0000" & result_reg WHEN io_mode = sgl_end ELSE
	            (15 DOWNTO 12 => result_reg(11)) & result_reg;

	--Free-running ADC conversion state machine
	PROCESS (clk, resetn)
	BEGIN
		IF resetn = '0' THEN
			state      <= IDLE;
			phase      <= POS;
			adc_start  <= '0';
			result_reg <= (OTHERS => '0');
			result_pos <= (OTHERS => '0');

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
				    --Differential mode implementation
					IF io_mode = diff THEN
						IF phase = POS THEN
							result_pos <= adc_result; -- store positive sample
							phase      <= NEG;
							state      <= IDLE;       -- go sample channel_neg
						ELSE
							--channel - channel_neg, sign-extend to 12 bits
							result_reg <= STD_LOGIC_VECTOR(
								RESIZE(SIGNED('0' & result_pos) - SIGNED('0' & adc_result), 12)
							);
							phase <= POS;
							state <= IDLE;
						END IF;
					
					--TTL debug mode implementation
					ELSE IF io_mode = ttl_debug THEN
						--input 0 800mV
						IF ttl_config = ttl_input_0 THEN
							result_reg <= STD_LOGIC_VECTOR
							RESIZE(SIGNED('0' & adc_result) - 800, 12);
						END IF;
						--output 0 400mV
						IF ttl_config = ttl_output_0 THEN
							result_reg <= STD_LOGIC_VECTOR
							RESIZE(SIGNED('0' & adc_result) - 400, 12);
						END IF;
						--input 1 2000mV
						IF ttl_config = ttl_input_1 THEN
							result_reg <= STD_LOGIC_VECTOR
							RESIZE(SIGNED('0' & adc_result) - 2000, 12);
						END IF;
						--output 1 2700mV
						IF ttl_config = ttl_output_1 THEN
							result_reg <= STD_LOGIC_VECTOR
							RESIZE(SIGNED('0' & adc_result) - 2700, 12);
						END IF;
					END IF;

					state <= IDLE; 
					-- Single-ended
					ELSE
						result_reg <= adc_result;
						state      <= IDLE;
					END IF;

			END CASE;
		END IF;
	END PROCESS;
	
END arch;
