LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;

-- TODO: Description goes here

ENTITY ADC IS
	PORT (
        -- from SCOMP
		io_addr	 : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        io_read  : IN STD_LOGIC;
		resetn 	 : IN STD_LOGIC;

        -- to SCOMP
        io_data  : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        io_en    : OUT STD_LOGIC
	);
END ADC;

ARCHITECTURE arch OF ADC IS
	TYPE MODE_TYPE IS ( sgl_endt, diff, ttl_debug, err );
	TYPE CHANNEL_TYPE IS ( ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7, ch_error);
	TYPE TTL_CONFIG IS ( ttl_input_0, ttl_input_1, ttl_output_0, ttl_output_1 );

	SIGNAL channel  : CHANNEL_TYPE;
	SIGNAL channel_neg : CHANNEL_TYPE;
	SIGNAL io_mode  : MODE_TYPE;
	SIGNAL ttl_config  : TTL_CONFIG;
	
BEGIN

	-- Combinationally select channel based on io_addr
	WITH io_addr(3 DOWNTO 0) SELECT
		channel <= ch0 WHEN "0000",
		           ch1 WHEN "0001",
		           ch2 WHEN "0010",
		           ch3 WHEN "0011",
		           ch4 WHEN "0100",
		           ch5 WHEN "0101",
		           ch6 WHEN "0110",
		           ch7 WHEN "0111",
		           ch_error WHEN OTHERS;
	
	WITH io_addr(10 DOWNTO 8) SELECT
	channel_neg <= ch0 WHEN "0000",
				ch1 WHEN "0001",
				ch2 WHEN "0010",
				ch3 WHEN "0011",
				ch4 WHEN "0100",
				ch5 WHEN "0101",
				ch6 WHEN "0110",
				ch7 WHEN "0111",
				ch_error WHEN OTHERS;

	WITH io_addr(5 DOWNTO 4) SELECT
		io_mode <=  sgl_end    WHEN "00",
					diff       WHEN "01",
		            ttl_debug  WHEN "10",
		            err    WHEN OTHERS;

	WITH io_addr(13 DOWNTO 12) SELECT
		ttl_config <=   ttl_input_0   WHEN "00",
					ttl_output_0       WHEN "01",
		            ttl_input_1  WHEN "10",
		            ttl_output_1    WHEN "11";

	
	-- Process block to update display memory, which in turn updates display output
	PROCESS (io_read, resetn)
	BEGIN
		
	END PROCESS;
	
END arch;
