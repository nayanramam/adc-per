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
	TYPE ADC_STATE IS (IDLE, CONVERTING, STORE);
	SIGNAL state_rnd  : ADC_STATE;
	SIGNAL result_reg : STD_LOGIC_VECTOR(11 DOWNTO 0);

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

	-- -- Instantiate the LTC2308 controller
	-- ltc : ENTITY work.LTC2308_ctrl


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



	--zero-pad in single-ended mode, sign-extend otherwise, also check for errors
	adc_data_reg <= X"DEAD" WHEN (channel = ch_error OR io_mode = err OR channel_neg = ch_error) ELSE
	            "0000" & result_reg WHEN io_mode = sgl_end ELSE
	            (15 DOWNTO 12 => result_reg(11)) & result_reg;

	-- TODO: change
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
	
	PROCESS (channel, channel_neg, io_mode, ttl_config,
	         buf_ch0, buf_ch1, buf_ch2, buf_ch3,
	         buf_ch4, buf_ch5, buf_ch6, buf_ch7)
		VARIABLE vpos : STD_LOGIC_VECTOR(11 DOWNTO 0);
		VARIABLE vneg : STD_LOGIC_VECTOR(11 DOWNTO 0);
	BEGIN
		vpos := "000000000000";
		vneg := "000000000000";

		IF io_mode = diff THEN
			CASE channel IS
				WHEN ch0 => vpos := buf_ch0;
				WHEN ch1 => vpos := buf_ch1;
				WHEN ch2 => vpos := buf_ch2;
				WHEN ch3 => vpos := buf_ch3;
				WHEN ch4 => vpos := buf_ch4;
				WHEN ch5 => vpos := buf_ch5;
				WHEN ch6 => vpos := buf_ch6;
				WHEN ch7 => vpos := buf_ch7;
				WHEN OTHERS => vpos := "000000000000";
			END CASE;
			CASE channel_neg IS
				WHEN ch0 => vneg := buf_ch0;
				WHEN ch1 => vneg := buf_ch1;
				WHEN ch2 => vneg := buf_ch2;
				WHEN ch3 => vneg := buf_ch3;
				WHEN ch4 => vneg := buf_ch4;
				WHEN ch5 => vneg := buf_ch5;
				WHEN ch6 => vneg := buf_ch6;
				WHEN ch7 => vneg := buf_ch7;
				WHEN OTHERS => vneg := "000000000000";
			END CASE;
			result_reg <= std_logic_vector(unsigned(vpos) - unsigned(vneg));

		ELSIF io_mode = sgl_end THEN
			CASE channel IS
				WHEN ch0 => result_reg <= buf_ch0;
				WHEN ch1 => result_reg <= buf_ch1;
				WHEN ch2 => result_reg <= buf_ch2;
				WHEN ch3 => result_reg <= buf_ch3;
				WHEN ch4 => result_reg <= buf_ch4;
				WHEN ch5 => result_reg <= buf_ch5;
				WHEN ch6 => result_reg <= buf_ch6;
				WHEN ch7 => result_reg <= buf_ch7;
				WHEN OTHERS => result_reg <= "000000000000";
			END CASE;

		ELSIF io_mode = ttl_debug THEN
			CASE channel IS
				WHEN ch0 => vpos := buf_ch0;
				WHEN ch1 => vpos := buf_ch1;
				WHEN ch2 => vpos := buf_ch2;
				WHEN ch3 => vpos := buf_ch3;
				WHEN ch4 => vpos := buf_ch4;
				WHEN ch5 => vpos := buf_ch5;
				WHEN ch6 => vpos := buf_ch6;
				WHEN ch7 => vpos := buf_ch7;
				WHEN OTHERS => vpos := "000000000000";
			END CASE;

			CASE ttl_config IS
				WHEN ttl_input_0 =>
					result_reg <= std_logic_vector(unsigned(vpos) - to_unsigned(800, 12));
				WHEN ttl_output_0 =>
					result_reg <= std_logic_vector(unsigned(vpos) - to_unsigned(400, 12));
				WHEN ttl_input_1 =>
					result_reg <= std_logic_vector(unsigned(vpos) - to_unsigned(2000, 12));
				WHEN ttl_output_1 =>
					result_reg <= std_logic_vector(unsigned(vpos) - to_unsigned(2700, 12));
				WHEN OTHERS =>
					result_reg <= "000000000000";
			END CASE;

		ELSE
			result_reg <= "000000000000";
		END IF;

	END PROCESS;

END arch;