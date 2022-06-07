----------------------------------------------------------------------------
--	GPIO_Demo.vhd -- Basys3 GPIO/UART Demonstration Project
----------------------------------------------------------------------------
-- Author:  Marshall Wingerson Adapted from Sam Bobrowicz
--          Copyright 2013 Digilent, Inc.
----------------------------------------------------------------------------
--
----------------------------------------------------------------------------
--	The GPIO/UART Demo project demonstrates a simple usage of the Basys3's 
--  GPIO and UART. The behavior is as follows:
--
--       *An introduction message is sent across the UART when the device
--        is finished being configured, and after the center User button
--        is pressed.
--       *A message is sent over UART whenever BTNU, BTNL, BTND, or BTNR is
--        pressed.
--       *Note that the center user button behaves as a user reset button
--        and is referred to as such in the code comments below
--        
--	All UART communication can be captured by attaching the UART port to a
-- computer running a Terminal program with 9600 Baud Rate, 8 data bits, no 
-- parity, and 1 stop bit.																
----------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.ALL;

--The IEEE.std_logic_unsigned contains definitions that allow 
--std_logic_vector types to be used with the + operator to instantiate a 
--counter.
use IEEE.std_logic_unsigned.all;


entity P998_UART is
    Port ( BTN 			: in   std_logic_vector(4 downto 0);
           CLK 			: in   std_logic;
           UART_TXD 	: out  std_logic);
end P998_UART;


architecture Behavioral of P998_UART is


component UART_TX
Port(
	SEND : in std_logic;
	DATA : in std_logic_vector(7 downto 0);
	CLK : in std_logic;          
	READY : out std_logic;
	UART_TX : out std_logic
	);
end component;


component debouncer
Generic(
        DEBNC_CLOCKS : integer;
        PORT_WIDTH : integer);
Port(
		SIGNAL_I : in std_logic_vector(4 downto 0);
		CLK_I : in std_logic;          
		SIGNAL_O : out std_logic_vector(4 downto 0)
		);
end component;



--The type definition for the UART state machine type. Here is a description of what
--occurs during each state:
-- RST_REG     -- Do Nothing. This state is entered after configuration or a user reset.
--                The state is set to LD_INIT_STR.
-- LD_INIT_STR -- The Welcome String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The welcome string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
-- SEND_CHAR   -- uartSend is set high for a single clock cycle, signaling the character
--                data at sendStr(strIndex) to be registered by the UART_TX at the next
--                cycle. Also, strIndex is incremented (behaves as if it were post 
--                incremented after reading the sendStr data). The state is set to RDY_LOW.
-- RDY_LOW     -- Do nothing. Wait for the READY signal from the UART_TX to go low, 
--                indicating a send operation has begun. State is set to WAIT_RDY.
-- WAIT_RDY    -- Do nothing. Wait for the READY signal from the UART_TX to go high, 
--                indicating a send operation has finished. If READY is high and strEnd = 
--                StrIndex then state is set to WAIT_BTN, else if READY is high and strEnd /=
--                StrIndex then state is set to SEND_CHAR.
-- WAIT_BTN    -- Do nothing. Wait for a button press on BTNU, BTNL, BTND, or BTNR. If a 
--                button press is detected, set the state to LD_BTN_STR.
-- LD_BTN_STR  -- The Button String is loaded into the sendStr variable and the strIndex
--                variable is set to zero. The button string length is stored in the StrEnd
--                variable. The state is set to SEND_CHAR.
type UART_STATE_TYPE is (RST_REG, LD_INIT_STR, SEND_CHAR, RDY_LOW, WAIT_RDY, WAIT_BTN, LD_BTN_STR);

--The CHAR_ARRAY type is a variable length array of 8 bit std_logic_vectors. 
--Each std_logic_vector contains an ASCII value and represents a character in
--a string. The character at index 0 is meant to represent the first
--character of the string, the character at index 1 is meant to represent the
--second character of the string, and so on.
type CHAR_ARRAY is array (integer range<>) of std_logic_vector(7 downto 0);

constant TMR_CNTR_MAX : std_logic_vector(26 downto 0) := "101111101011110000100000000"; --100,000,000 = clk cycles per second
constant TMR_VAL_MAX : std_logic_vector(3 downto 0) := "1001"; --9

constant RESET_CNTR_MAX : std_logic_vector(17 downto 0) := "110000110101000000";-- 100,000,000 * 0.002 = 200,000 = clk cycles per 2 ms

constant MAX_STR_LEN : integer := 66;

constant WELCOME_STR_LEN : natural := 27;

--Welcome string definition. Note that the values stored at each index
--are the ASCII values of the indicated character.
constant WELCOME_STR : CHAR_ARRAY(0 to 26) := (X"0A",  --\n
															  X"0D",  --\r
															  X"42",  --B
															  X"41",  --A
															  X"53",  --S
															  X"59",  --Y
															  X"53",  --S
															  X"33",  --3
															  X"20",  -- 
															  X"47",  --G
															  X"50",  --P10
															  X"49",  --I
															  X"4F",  --O
															  X"2F",  --/
															  X"55",  --U
															  X"41",  --A
															  X"52",  --R
															  X"54",  --T
															  X"20",  -- 
															  X"44",  --D
															  X"45",  --E20
															  X"4D",  --M
															  X"4F",  --O
															  X"21",  --!
															  X"0A",  --\n
															  X"0A",  --\n
															  X"0D"); --\r
															  
--Button press string definition.

constant BTND_STR : CHAR_ARRAY(0 to 31) := (X"59",  --Y
															  X"6F",  --o
															  X"75",  --u
															  X"20",  -- 
															  X"70",  --p
															  X"72",  --r
															  X"65",  --e
															  X"73",  --s
															  X"73",  --s
															  X"65",  --e10
															  X"64",  --d
															  X"20",  -- 
															  X"42",  --B
															  X"54",  --T
															  X"4E",  --N
															  X"44",  --D
															  x"20",  -- 
															  x"28",  --(
															  x"44",  --D
															  x"6F",  --o20
															  x"77",  --w
															  x"6E",  --n
															  x"20",  -- 
															  x"62",  --b
															  X"75",  --u
															  X"74",  --t
															  X"74",  --t
															  X"6F",  --o
															  X"6E",  --n
															  X"29",  --)30
															  X"0A",  --\n
															  X"0D"); --\r33
															  
constant BTNU_STR : CHAR_ARRAY(0 to 29) :=															  ------------
															  (X"59",  --Y
															  X"6F",  --o
															  X"75",  --u
															  X"20",  -- 
															  X"70",  --p
															  X"72",  --r
															  X"65",  --e
															  X"73",  --s
															  X"73",  --s
															  X"65",  --e
															  X"64",  --d
															  X"20",  -- 
															  X"42",  --B
															  X"54",  --T
															  X"4E",  --N
															  X"55",  --U
															  x"20",  -- 
															  x"28",  --(
															  x"55",  --U
															  x"70",  --p
															  x"20",  -- 
															  x"62",  --b
															  X"75",  --u
															  X"74",  --t
															  X"74",  --t
															  X"6F",  --o
															  X"6E",  --n
															  X"29",  --)
															  X"0A",  --\n
															  X"0D"); --\r
															  
constant BTNL_STR : CHAR_ARRAY(0 to 31) :=															  ------------
															  (X"59",  --Y
															  X"6F",  --o
															  X"75",  --u
															  X"20",  -- 
															  X"70",  --p
															  X"72",  --r
															  X"65",  --e
															  X"73",  --s
															  X"73",  --s
															  X"65",  --e
															  X"64",  --d
															  X"20",  -- 
															  X"42",  --B
															  X"54",  --T
															  X"4E",  --N
															  X"4C",  --L
															  x"20",  -- 
															  x"28",  --(
															  x"4C",  --L
															  x"65",  --e
															  x"66",  --f
															  x"74",  --t
															  x"20",  -- 
															  x"62",  --b
															  X"75",  --u
															  X"74",  --t
															  X"74",  --t
															  X"6F",  --o
															  X"6E",  --n
															  X"29",  --)
															  X"0A",  --\n
															  X"0D"); --\r
															 
constant BTNR_STR : CHAR_ARRAY(0 to 32) :=											  ------------
															  (X"59",  --Y
															  X"6F",  --o
															  X"75",  --u
															  X"20",  -- 
															  X"70",  --p
															  X"72",  --r
															  X"65",  --e
															  X"73",  --s
															  X"73",  --s
															  X"65",  --e
															  X"64",  --d
															  X"20",  -- 
															  X"42",  --B
															  X"54",  --T
															  X"4E",  --N
															  X"52",  --R
															  x"20",  -- 
															  x"28",  --(
															  x"52",  --R
															  x"69",  --i
															  x"67",  --g
															  x"68",  --h
															  x"74",  --t
															  x"20",  -- 
															  x"62",  --b
															  X"75",  --u
															  X"74",  --t
															  X"74",  --t
															  X"6F",  --o
															  X"6E",  --n
															  X"29",  --)
															  X"0A",  --\n
															  X"0D"); --\r
															  
constant BTN_START : CHAR_ARRAY(0 to 14) := (X"59",  --Y
															  X"6F",  --o
															  X"75",  --u
															  X"20",  -- 
															  X"70",  --p
															  X"72",  --r
															  X"65",  --e
															  X"73",  --s
															  X"73",  --s
															  X"65",  --e
															  X"64",  --d
															  X"20",  -- 
															  X"42",  --B
															  X"54",  --T
															  X"4E");  --N
															  
constant BTN_END : CHAR_ARRAY(0 to 9) := (x"20",  -- 
															  x"62",  --b
															  X"75",  --u
															  X"74",  --t
															  X"74",  --t
															  X"6F",  --o
															  X"6E",  --n
															  X"29",  --)
															  X"0A",  --\n
															  X"0D"); --\r
constant BTND_SAVE : CHAR_ARRAY(0 to 6) := (X"44",  --D
															  x"20",  -- 
															  x"28",  --(
															  x"44",  --D
															  x"6F",  --o20
															  x"77",  --w
															  x"6E");  --n
constant BTNU_SAVE: CHAR_ARRAY(0 to 4) := (X"55",  --U
															  x"20",  -- 
															  x"28",  --(
															  x"55",  --U
															  x"70");  --p
constant BTNL_SAVE : CHAR_ARRAY(0 to 6) := (X"4C",  --L
															  x"20",  -- 
															  x"28",  --(
															  x"4C",  --L
															  x"65",  --e
															  x"66",  --f
															  x"74");  --t
constant BTNR_SAVE : CHAR_ARRAY(0 to 7)	 := (X"52",  --R
															  x"20",  -- 
															  x"28",  --(
															  x"52",  --R
															  x"69",  --i
															  x"67",  --g
															  x"68",  --h
															  x"74");  --t

--Contains the current string being sent over uart.
signal sendStr : CHAR_ARRAY(0 to (MAX_STR_LEN - 1));

--Contains the length of the current string being sent over uart.
signal strEnd : natural;

--Contains the index of the next character to be sent over uart
--within the sendStr variable.
signal strIndex : natural;

--Used to determine when a button press has occured
signal btnReg : std_logic_vector (3 downto 0) := "0000";
signal btnDetect : std_logic;

--UART_TX control signals
signal uartRdy : std_logic;
signal uartSend : std_logic := '0';
signal uartData : std_logic_vector (7 downto 0):= "00000000";
signal uartTX : std_logic;

--Current uart state signal
signal uartState : UART_STATE_TYPE := RST_REG;

--Debounced btn signals used to prevent single button presses
--from being interpreted as multiple button presses.
signal btnDeBnc : std_logic_vector(4 downto 0);

signal clk_cntr_reg : std_logic_vector (4 downto 0) := (others=>'0'); 

signal pwm_val_reg : std_logic := '0';

--this counter counts the amount of time paused in the UART reset state
signal reset_cntr : std_logic_vector (17 downto 0) := (others=>'0');

begin



----------------------------------------------------------
------              Button Control                 -------
----------------------------------------------------------
--Buttons are debounced and their rising edges are detected
--to trigger UART messages


--Debounces btn signals
Inst_btn_debounce: debouncer 
    generic map(
        DEBNC_CLOCKS => (2**16),
        PORT_WIDTH => 5)
    port map(
		SIGNAL_I => BTN,
		CLK_I => CLK,
		SIGNAL_O => btnDeBnc
	);


--Registers the debounced button signals, for edge detection.
btn_reg_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		btnReg <= btnDeBnc(3 downto 0);
	end if;
end process;


--btnDetect goes high for a single clock cycle when a btn press is
--detected. This triggers a UART message to begin being sent.
btnDetect <= '1' when ((btnReg(0)='0' and btnDeBnc(0)='1') or
								(btnReg(1)='0' and btnDeBnc(1)='1') or
								(btnReg(2)='0' and btnDeBnc(2)='1') or
								(btnReg(3)='0' and btnDeBnc(3)='1')) 
				 else   
		     '0';
				  



----------------------------------------------------------
------              UART Control                   -------
----------------------------------------------------------
--Messages are sent on reset and when a button is pressed.

--This counter holds the UART state machine in reset for ~2 milliseconds. This
--will complete transmission of any byte that may have been initiated during 
--FPGA configuration due to the UART_TX line being pulled low, preventing a 
--frame shift error from occuring during the first message.
process(CLK)
begin
  if (rising_edge(CLK)) then
    if ((reset_cntr = RESET_CNTR_MAX) or (uartState /= RST_REG)) then
      reset_cntr <= (others=>'0');
    else
      reset_cntr <= std_logic_vector(reset_cntr + 1);
    end if;
  end if;
end process;



--Next Uart state logic (states described above)
next_uartState_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (btnDeBnc(4) = '1') then
			uartState <= RST_REG;
		else	
			case uartState is 
			when RST_REG =>
        if (reset_cntr = RESET_CNTR_MAX) then
          uartState <= LD_INIT_STR;
        end if;
			when LD_INIT_STR =>
				uartState <= SEND_CHAR;
			when SEND_CHAR =>
				uartState <= RDY_LOW;
			when RDY_LOW =>
				uartState <= WAIT_RDY;
			when WAIT_RDY =>
				if (uartRdy = '1') then
					if (strEnd = strIndex) then
						uartState <= WAIT_BTN;
					else
						uartState <= SEND_CHAR;
					end if;
				end if;
			when WAIT_BTN =>
				if (btnDetect = '1') then
					uartState <= LD_BTN_STR;
				end if;
			when LD_BTN_STR =>
				uartState <= SEND_CHAR;
			when others=> --should never be reached
				uartState <= RST_REG;
			end case;
		end if ;
	end if;
end process;


--Loads the sendStr and strEnd signals when a LD state is
--is reached.
string_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR) then
			sendStr(0 to 26) <= WELCOME_STR;
			strEnd <= WELCOME_STR_LEN;
		elsif (uartState = LD_BTN_STR) then
		    if(btnDeBnc(3) = '1') then
			 sendStr(0 to 63) <= BTND_STR & BTN_START & BTND_SAVE & BTN_END;
			 strEnd <= 64;
			elsif (btnDeBnc(0) = '1') then
			 sendStr(0 to 59) <= BTNU_STR & BTN_START & BTNU_SAVE & BTN_END;
			 strEnd <= 60;
		    elsif (btnDeBnc(1) = '1') then
		      sendStr(0 to 63) <= BTNL_STR & BTN_START & BTNL_SAVE & BTN_END;
		      strEnd <= 64;
		    elsif (btnDeBnc(2) = '1') then
		      sendStr(0 to 65) <= BTNR_STR & BTN_START & BTNR_SAVE & BTN_END;
		      strEnd <= 66;
		    end if;
		end if;
	end if;
end process;


--Conrols the strIndex signal so that it contains the index
--of the next character that needs to be sent over uart
char_count_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = LD_INIT_STR or uartState = LD_BTN_STR) then
			strIndex <= 0;
		elsif (uartState = SEND_CHAR) then
			strIndex <= strIndex + 1;
		end if;
	end if;
end process;


--Controls the UART_TX signals
char_load_process : process (CLK)
begin
	if (rising_edge(CLK)) then
		if (uartState = SEND_CHAR) then
			uartSend <= '1';
			uartData <= sendStr(strIndex);
		else
			uartSend <= '0';
		end if;
	end if;
end process;


--Component used to send a byte of data over a UART line.
Inst_UART_TX: UART_TX port map(
		SEND => uartSend,
		DATA => uartData,
		CLK => CLK,
		READY => uartRdy,
		UART_TX => uartTX 
	);

UART_TXD <= uartTX;


end Behavioral;
