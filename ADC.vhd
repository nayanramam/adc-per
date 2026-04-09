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
	TYPE MODE_TYPE IS ( m_default, m_ttl_debug );
	TYPE CHANNEL_TYPE IS ( ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7 );
	TYPE TTL_SEL_TYPE IS ( ttl_input, ttl_output );
	TYPE LOG_SEL_TYPE IS ( logic_low, logic_high );

	SIGNAL channel  : CHANNEL_TYPE;
	SIGNAL io_mode  : MODE_TYPE;
	SIGNAL ttl_sel  : TTL_SEL_TYPE;
	SIGNAL log_sel  : LOG_SEL_TYPE;
	
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
		   --      0xDEAD WHEN OTHERS;

	WITH io_addr(5 DOWNTO 4) SELECT
		io_mode <=  sgl_end    WHEN "00",
					diff       WHEN "01",
		            ttl_debug  WHEN "10",
		            sgl_end    WHEN OTHERS;

	WITH io_addr(4) SELECT
		ttl_sel <=  ttl_input  WHEN '0',
		            ttl_output WHEN '1',
		            ttl_input  WHEN OTHERS;

	WITH io_addr(5) SELECT
		log_sel <=  logic_low  WHEN '0',
		            logic_high WHEN '1',
		            logic_low  WHEN OTHERS;
	
	-- Process block to update display memory, which in turn updates display output
	PROCESS (io_read, resetn)
	BEGIN
		
	END PROCESS;
	
END arch;
