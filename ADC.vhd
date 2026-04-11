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
	TYPE TTL_CONFIG IS ( ttl_input_0, ttl_input_1, ttl_output_0, ttl_output_1, ttl_error );
	
	-- SCOMP Communication Signals	
	SIGNAL channel  : CHANNEL_TYPE;
	SIGNAL channel_neg : CHANNEL_TYPE;
	SIGNAL io_mode  : MODE_TYPE;
	SIGNAL ttl_config  : TTL_CONFIG;
	
	-- FSM for round-robin ADC sampling
	TYPE ADC_STATE IS (IDLE, CONVERTING, STORE);
	SIGNAL state_rnd  : ADC_STATE;
	SIGNAL result_pos : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL result_neg : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL result_reg : STD_LOGIC_VECTOR(11 DOWNTO 0);

	-- ADC LTC2308 Controller Info Signals
	SIGNAL adc_busy   : STD_LOGIC;
	SIGNAL adc_start  : STD_LOGIC;
	SIGNAL adc_result : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL cfg_word   : STD_LOGIC_VECTOR(5 DOWNTO 0);

	-- Buffer Registers for ADC Data
	SIGNAL buf_ch0 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch1 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch2 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch3 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch4 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch5 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch6 : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL buf_ch7 : STD_LOGIC_VECTOR(11 DOWNTO 0);

	SIGNAL ch_count : INTEGER RANGE 0 TO 7;

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

	-- Port mapping for the SCOMP 
    PORT MAP (
		clock    => clk,
		resetn => resetn,
		IO_WRITE => config,
		IO_READ => adc_data
    );


	

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
		            ttl_output_1    WHEN "11",
		            ttl_error WHEN OTHERS;



	--zero-pad in single-ended mode, sign-extend otherwise, also check for errors
	adc_data <= X"DEAD" WHEN (channel = ch_error OR io_mode = err OR channel_neg = ch_error) ELSE
	            "0000" & result_reg WHEN io_mode = sgl_end ELSE
	            (15 DOWNTO 12 => result_reg(11)) & result_reg;

	-- Round-robin ADC sampling state machine
	PROCESS (clk, resetn)
	BEGIN	
		IF resetn = '0' THEN
			state_rnd  <= IDLE;
			adc_start  <= '0';

		ELSIF rising_edge(clk) THEN
			CASE state_rnd IS

				WHEN IDLE =>
					ch_count <= 0;
					adc_start <= '0';
					state_rnd <= CONVERTING;
					-- Choose configuration word to send to ADC based on active_channel
					CASE ch_count IS
						WHEN 0 =>
							cfg_word <= "100010";
						WHEN 1 =>
							cfg_word <= "100110";
						WHEN 2 =>
							cfg_word <= "101010";
						WHEN 3 =>
							cfg_word <= "101110";
						WHEN 4 =>
							cfg_word <= "110010";
						WHEN 5 =>
							cfg_word <= "110110";
						WHEN 6 =>
							cfg_word <= "111010";
						WHEN 7 =>
							cfg_word <= "111110";
						WHEN OTHERS =>
							cfg_word <= "000000";
					END CASE;

				WHEN CONVERTING =>
					adc_start <= '1';
					IF adc_busy = '1' THEN
						state_rnd <= STORE;
					END IF;

				
				WHEN STORE =>
					adc_start <= '0';
					CASE ch_count IS
						WHEN 0 =>
							buf_ch0 <= adc_result;
						WHEN 1 =>
							buf_ch1 <= adc_result;
						WHEN 2 =>
							buf_ch2 <= adc_result;
						WHEN 3 =>
							buf_ch3 <= adc_result;
						WHEN 4 =>
							buf_ch4 <= adc_result;
						WHEN 5 =>
							buf_ch5 <= adc_result;
						WHEN 6 =>
							buf_ch6 <= adc_result;
						WHEN 7 =>
							buf_ch7 <= adc_result;
						WHEN OTHERS =>
							NULL;
					END CASE;
					ch_count <= (ch_count + 1) MOD 8;
					state_rnd <= CONVERTING;

				WHEN OTHERS =>
					state_rnd <= IDLE;
			END CASE;
		END IF;
	END PROCESS;
	
	PROCESS (channel, channel_neg, io_mode, ttl_config)
	BEGIN
		IF io_mode = diff THEN
			WITH channel SELECT
			result_pos <= buf_ch0 WHEN ch0,
		       		      buf_ch1 WHEN ch1,
		          		  buf_ch2 WHEN ch2,
		           		  buf_ch3 WHEN ch3,
						  buf_ch4 WHEN ch4,
						  buf_ch5 WHEN ch5,
						  buf_ch6 WHEN ch6,
						  buf_ch7 WHEN ch7,
						  "000000000000" WHEN OTHERS;
			WITH channel_neg SELECT
			result_neg <= buf_ch0 WHEN ch0,
		       		      buf_ch1 WHEN ch1,
		          		  buf_ch2 WHEN ch2,
		           		  buf_ch3 WHEN ch3,
						  buf_ch4 WHEN ch4,
						  buf_ch5 WHEN ch5,
						  buf_ch6 WHEN ch6,
						  buf_ch7 WHEN ch7,
						  "000000000000" WHEN OTHERS;
			result_reg <= result_pos - result_neg;

		ELSIF io_mode = sgl_end THEN
			WITH channel SELECT
			result_reg <= buf_ch0 WHEN ch0,
		       		      buf_ch1 WHEN ch1,
		          		  buf_ch2 WHEN ch2,
		           		  buf_ch3 WHEN ch3,
						  buf_ch4 WHEN ch4,
						  buf_ch5 WHEN ch5,
						  buf_ch6 WHEN ch6,
						  buf_ch7 WHEN ch7,
						  "000000000000" WHEN OTHERS;

		ELSIF io_mode = ttl_debug THEN
		    WITH channel SELECT
			result_pos <= buf_ch0 WHEN ch0,
		       		      buf_ch1 WHEN ch1,
		          		  buf_ch2 WHEN ch2,
		           		  buf_ch3 WHEN ch3,
						  buf_ch4 WHEN ch4,
						  buf_ch5 WHEN ch5,
						  buf_ch6 WHEN ch6,
						  buf_ch7 WHEN ch7,
						  "000000000000" WHEN OTHERS;

			WITH ttl_config SELECT
			result_reg <= result_pos - 800 WHEN ttl_input_0,
						  result_pos - 400 WHEN ttl_output_0,
						  result_pos - 2000 WHEN ttl_input_1,
						  result_pos - 2700 WHEN ttl_output_1,
						  "000000000000" WHEN OTHERS;

		ELSE
			result_reg <= "000000000000";
		END IF;

	END PROCESS;

END arch;