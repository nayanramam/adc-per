LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.NUMERIC_STD.all;

ENTITY ADC IS
	PORT (
        -- SYSTEM SIGNALS
		clk    : IN STD_LOGIC;
		resetn : IN STD_LOGIC;
		io_read : IN STD_LOGIC;
		io_write : IN STD_LOGIC;
		io_addr : IN STD_LOGIC_VECTOR(10 DOWNTO 0);

		-- R/W TO SCOMP
        adc_data  : INOUT STD_LOGIC_VECTOR(15 DOWNTO 0);

		-- ADC LTC2308 Controller Info Signals
		adc_busy   : IN STD_LOGIC;
		adc_start  : OUT STD_LOGIC;
		adc_result : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
		cfg_word   : OUT STD_LOGIC_VECTOR(5 DOWNTO 0)



	);
END ADC;

ARCHITECTURE arch OF ADC IS
	-- SCOMP Communication Enum Types
	TYPE MODE_TYPE IS ( sgl_end, diff, ttl_debug, err );
	TYPE CHANNEL_TYPE IS ( ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7, ch_error);
	TYPE TTL_CONFIG_TYPE IS ( ttl_input_0, ttl_input_1, ttl_output_0, ttl_output_1, ttl_error );
	
	-- SCOMP Communication Signals	
	SIGNAL channel  : CHANNEL_TYPE;
	SIGNAL channel_neg : CHANNEL_TYPE;
	SIGNAL io_mode  : MODE_TYPE;
	SIGNAL ttl_config  : TTL_CONFIG_TYPE;
	
	-- FSM for round-robin ADC sampling
	TYPE ADC_STATE IS (IDLE, CONVERTING, WAIT_BUSY, STORE);
	SIGNAL state_rnd  : ADC_STATE;

	-- Combinational sample path
	SIGNAL vpos         : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL vneg         : STD_LOGIC_VECTOR(11 DOWNTO 0);
	SIGNAL sample_diff  : STD_LOGIC_VECTOR(15 DOWNTO 0);
	SIGNAL sample_ttl   : STD_LOGIC_VECTOR(15 DOWNTO 0);

	-- Latch for Config
	SIGNAL config_data_lat : STD_LOGIC_VECTOR(15 DOWNTO 0);
	-- Reg for Output
	SIGNAL adc_data_reg : STD_LOGIC_VECTOR(15 DOWNTO 0);

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
	-- Combinationally select channel based on config
	WITH config_data_lat(4 DOWNTO 2) SELECT
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
	WITH config_data_lat(1 DOWNTO 0) SELECT
		io_mode <=  sgl_end    WHEN "00",
					diff       WHEN "01",
		            ttl_debug  WHEN "10",
		            err    WHEN OTHERS;

	-- Combinationally select negative channel based on config			   
	WITH config_data_lat(7 DOWNTO 5) SELECT
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
	WITH config_data_lat(9 DOWNTO 8) SELECT
		ttl_config <=   ttl_input_0   WHEN "00",
					ttl_output_0       WHEN "01",
		            ttl_input_1  WHEN "10",
		            ttl_output_1    WHEN "11",
		            ttl_error WHEN OTHERS;

	-- Channel / channel_neg muxes into sample path
	WITH channel SELECT
		vpos <= buf_ch0 WHEN ch0,
		        buf_ch1 WHEN ch1,
		        buf_ch2 WHEN ch2,
		        buf_ch3 WHEN ch3,
		        buf_ch4 WHEN ch4,
		        buf_ch5 WHEN ch5,
		        buf_ch6 WHEN ch6,
		        buf_ch7 WHEN ch7,
		        "000000000000" WHEN OTHERS;

	WITH channel_neg SELECT
		vneg <= buf_ch0 WHEN ch0,
		        buf_ch1 WHEN ch1,
		        buf_ch2 WHEN ch2,
		        buf_ch3 WHEN ch3,
		        buf_ch4 WHEN ch4,
		        buf_ch5 WHEN ch5,
		        buf_ch6 WHEN ch6,
		        buf_ch7 WHEN ch7,
		        "000000000000" WHEN OTHERS;

	-- Diff: full 16-bit subtraction (range is -4095..+4095, needs >12 bits)
	sample_diff <= std_logic_vector(
		("0000" & unsigned(vpos)) - ("0000" & unsigned(vneg))
	);

	-- TTL: full 16-bit subtraction against fixed thresholds
	WITH ttl_config SELECT
		sample_ttl <=
			std_logic_vector(("0000" & unsigned(vpos)) - to_unsigned(800, 16))  WHEN ttl_input_0,
			std_logic_vector(("0000" & unsigned(vpos)) - to_unsigned(400, 16))  WHEN ttl_output_0,
			std_logic_vector(("0000" & unsigned(vpos)) - to_unsigned(2000, 16)) WHEN ttl_input_1,
			std_logic_vector(("0000" & unsigned(vpos)) - to_unsigned(2700, 16)) WHEN ttl_output_1,
			X"0000" WHEN OTHERS;

	-- Pack 16-bit output: DEAD on error, zero-padded for single-ended, full width otherwise
	adc_data_reg <= X"DEAD" WHEN (channel = ch_error OR io_mode = err OR channel_neg = ch_error) ELSE
	            "0000" & vpos    WHEN io_mode = sgl_end ELSE
	            sample_diff      WHEN io_mode = diff ELSE
	            sample_ttl       WHEN io_mode = ttl_debug ELSE
	            X"0000";

	adc_data <= adc_data_reg WHEN io_read = '1' AND io_addr = "00000000011" ELSE (OTHERS => 'Z');

	-- Process to latch config data
	PROCESS (clk, resetn)
	BEGIN
		IF resetn = '0' THEN
			config_data_lat <= (OTHERS => '0');
		ELSIF rising_edge(clk) THEN
			IF io_write = '1' AND io_addr = "00000000011" THEN
				config_data_lat <= adc_data;
			END IF;
			
		END IF;
	END PROCESS;


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
					cfg_word <= "100010";
					state_rnd <= CONVERTING;
					

				WHEN CONVERTING =>
					IF adc_busy = '0' THEN
						adc_start <= '1';
						state_rnd <= WAIT_BUSY;
					ELSE
						state_rnd <= CONVERTING;
					END IF;

				WHEN WAIT_BUSY =>
					adc_start <= '0';
					IF adc_busy = '1' THEN
						state_rnd <= WAIT_BUSY;
					ELSE
						state_rnd <= STORE;
					END IF;

					
				WHEN STORE =>
					adc_start <= '0';
					CASE ch_count IS
						WHEN 0 =>
							buf_ch7 <= adc_result;
						WHEN 1 =>
							buf_ch0 <= adc_result;
						WHEN 2 =>
							buf_ch1 <= adc_result;
						WHEN 3 =>
							buf_ch2 <= adc_result;
						WHEN 4 =>
							buf_ch3 <= adc_result;
						WHEN 5 =>
							buf_ch4 <= adc_result;
						WHEN 6 =>
							buf_ch5 <= adc_result;
						WHEN 7 =>
							buf_ch6 <= adc_result;
						WHEN OTHERS =>
							NULL;
					END CASE;

					-- Choose configuration word to send to ADC based on active_channel
					-- LTC2308 cfg_word format: [S/D, ODD, A2, A1, UNI, SLP]
					-- ODD bit interleaves even/odd channels, so channels must be
					-- addressed in the order CH0,CH1,CH2,...CH7 using their correct words.
					CASE (ch_count + 1) MOD 8 IS
						WHEN 0 =>
							cfg_word <= "100010"; -- CH0: S/D=1, ODD=0, A2=0, A1=0
						WHEN 1 =>
							cfg_word <= "110010"; -- CH1: S/D=1, ODD=1, A2=0, A1=0
						WHEN 2 =>
							cfg_word <= "100110"; -- CH2: S/D=1, ODD=0, A2=0, A1=1
						WHEN 3 =>
							cfg_word <= "110110"; -- CH3: S/D=1, ODD=1, A2=0, A1=1
						WHEN 4 =>
							cfg_word <= "101010"; -- CH4: S/D=1, ODD=0, A2=1, A1=0
						WHEN 5 =>
							cfg_word <= "111010"; -- CH5: S/D=1, ODD=1, A2=1, A1=0
						WHEN 6 =>
							cfg_word <= "101110"; -- CH6: S/D=1, ODD=0, A2=1, A1=1
						WHEN 7 =>
							cfg_word <= "111110"; -- CH7: S/D=1, ODD=1, A2=1, A1=1
						WHEN OTHERS =>
							cfg_word <= "000000";
					END CASE;

					ch_count <= (ch_count + 1) MOD 8;
					state_rnd <= CONVERTING;

				WHEN OTHERS =>
					state_rnd <= IDLE;
			END CASE;
		END IF;
	END PROCESS;

END arch;