"""
Lightweight SCOMP simulator for testing ADC demo assembly programs.
Executes .mif files, mocks ADC channel buffers, and verifies HEX/LED outputs.
"""

import re, sys

# ---------------------------------------------------------------------------
# MIF loader
# ---------------------------------------------------------------------------
def load_mif(path):
    """Return dict {int_addr: int_word} from a Quartus MIF file."""
    mem = {}
    in_content = False
    for line in open(path):
        line = line.split("--")[0].strip().rstrip(";").strip()
        if not line:
            continue
        if "CONTENT" in line.upper():
            in_content = True
            continue
        if "BEGIN" in line.upper() or "END" in line.upper():
            continue
        if not in_content:
            continue
        # Handle range defaults like [000..7FF] : 0000
        m = re.match(r"\[([0-9A-Fa-f]+)\.\.([0-9A-Fa-f]+)\]\s*:\s*([0-9A-Fa-f]+)", line)
        if m:
            lo, hi, val = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16)
            for a in range(lo, hi + 1):
                mem[a] = val
            continue
        # Handle single address like 003 : 1234
        m = re.match(r"([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)", line)
        if m:
            mem[int(m.group(1), 16)] = int(m.group(2), 16)
    return mem


# ---------------------------------------------------------------------------
# 16-bit two's complement helpers
# ---------------------------------------------------------------------------
def to_s16(v):
    v &= 0xFFFF
    return v if v < 0x8000 else v - 0x10000

def to_u16(v):
    return v & 0xFFFF


# ---------------------------------------------------------------------------
# SCOMP Simulator
# ---------------------------------------------------------------------------
class SCOMP:
    def __init__(self, mif_path):
        self.mem = load_mif(mif_path)
        self.pc = 0
        self.ac = 0          # 16-bit accumulator (stored as signed python int)
        self.stack = []       # call/return stack

        # IO state
        self.adc_config = 0   # last config written to ADC port
        self.adc_channels = [0] * 8   # simulated 12-bit channel buffers
        self.timer_count = 0
        self.hex_up = 0       # HEX5-HEX4
        self.hex_lo = 0       # HEX3-HEX0
        self.leds = 0

        # Tracking
        self.cycle = 0
        self.outputs = []     # list of (cycle, port_name, value)

    def rd(self, addr):
        return self.mem.get(addr, 0)

    def wr(self, addr, val):
        self.mem[addr] = to_u16(val)

    def set_channels(self, ch_vals):
        """Set ADC channel values: dict {ch_num: 12-bit value}."""
        for ch, v in ch_vals.items():
            self.adc_channels[ch] = v & 0xFFF

    def _adc_read(self):
        """Compute the value SCOMP would read from the ADC peripheral,
        mirroring the combinational logic in ADC.vhd."""
        cfg = self.adc_config
        mode = cfg & 0x3
        ch_pos = (cfg >> 2) & 0x7
        ch_neg = (cfg >> 5) & 0x7
        ttl_sel = (cfg >> 8) & 0x3

        vpos = self.adc_channels[ch_pos]
        vneg = self.adc_channels[ch_neg]

        if mode == 0:   # single-ended
            return vpos & 0xFFF
        elif mode == 1: # differential
            diff = vpos - vneg      # can be negative
            return to_u16(diff)     # 16-bit two's complement
        elif mode == 2: # ttl_debug
            thresholds = {0: 800, 1: 400, 2: 2000, 3: 2700}
            result = vpos - thresholds[ttl_sel]
            return to_u16(result)
        else:
            return 0xDEAD

    def _io_read(self, port):
        if port == 2:   # TIMER
            return self.timer_count & 0xFFFF
        elif port == 3: # ADC
            return self._adc_read()
        else:
            return 0

    def _io_write(self, port, val):
        val = to_u16(val)
        if port == 1:   # LEDS
            self.leds = val
            self.outputs.append((self.cycle, "LEDS", val))
        elif port == 2: # TIMER
            self.timer_count = 0
        elif port == 3: # ADC config
            self.adc_config = val
        elif port == 4: # HEX_UP
            self.hex_up = val
            self.outputs.append((self.cycle, "HEX_UP", val))
        elif port == 5: # HEX_LO
            self.hex_lo = val
            self.outputs.append((self.cycle, "HEX_LO", val))

    def step(self):
        """Execute one instruction. Returns False if stuck in a tight loop."""
        ir = self.rd(self.pc)
        opcode = (ir >> 11) & 0x1F
        operand = ir & 0x7FF

        self.pc = (self.pc + 1) & 0x7FF
        self.cycle += 1

        # Increment timer every 10 instructions (simulates 10 Hz at ~100 instr/tick)
        if self.cycle % 10 == 0:
            self.timer_count += 1

        ac = to_s16(self.ac)
        mem_val = to_s16(self.rd(operand))

        if opcode == 0x00:   # NOP
            pass
        elif opcode == 0x01: # LOAD
            self.ac = to_u16(mem_val)
        elif opcode == 0x02: # STORE
            self.wr(operand, self.ac)
        elif opcode == 0x03: # LOADI (sign-extend 11-bit immediate)
            imm = operand if operand < 1024 else operand - 2048
            self.ac = to_u16(imm)
        elif opcode == 0x04: # ADD
            self.ac = to_u16(ac + mem_val)
        elif opcode == 0x05: # SUB
            self.ac = to_u16(ac - mem_val)
        elif opcode == 0x06: # ADDI (sign-extend 11-bit immediate)
            imm = operand if operand < 1024 else operand - 2048
            self.ac = to_u16(ac + imm)
        elif opcode == 0x07: # AND
            self.ac = to_u16(self.ac & to_u16(mem_val))
        elif opcode == 0x08: # OR
            self.ac = to_u16(self.ac | to_u16(mem_val))
        elif opcode == 0x09: # XOR
            self.ac = to_u16(self.ac ^ to_u16(mem_val))
        elif opcode == 0x0A: # SHIFT
            # operand bits: [10:5] = zero, [4:0] = shift spec
            # shift spec is sign-magnitude: bit4 = sign (1=right), [3:0] = distance
            spec = ir & 0x1F
            sign = (spec >> 4) & 1
            dist = spec & 0xF
            if sign == 0:  # left
                self.ac = to_u16(self.ac << dist)
            else:          # right (logical)
                self.ac = to_u16(self.ac >> dist)
        elif opcode == 0x0B: # JUMP
            self.pc = operand
        elif opcode == 0x0C: # JNEG
            if ac < 0:
                self.pc = operand
        elif opcode == 0x0D: # JPOS
            if ac > 0:
                self.pc = operand
        elif opcode == 0x0E: # JZERO
            if ac == 0:
                self.pc = operand
        elif opcode == 0x0F: # JNZ
            if ac != 0:
                self.pc = operand
        elif opcode == 0x10: # CALL
            self.stack.append(self.pc)
            self.pc = operand
        elif opcode == 0x11: # RETURN
            self.pc = self.stack.pop()
        elif opcode == 0x12: # IN
            self.ac = to_u16(self._io_read(operand))
        elif opcode == 0x13: # OUT
            self._io_write(operand, self.ac)
        else:
            pass

        return True

    def run(self, max_cycles=50000):
        """Run until max_cycles or until the same PC is hit 3x in a row (spin loop)."""
        prev_pc = -1
        spin = 0
        for _ in range(max_cycles):
            pc_before = self.pc
            self.step()
            if self.pc == pc_before == prev_pc:
                spin += 1
                if spin > 5:
                    break
            else:
                spin = 0
            prev_pc = pc_before


# ---------------------------------------------------------------------------
# Hex display decoder -- turns 4-bit nibble into human-readable char
# ---------------------------------------------------------------------------
def decode_hex_display(val16):
    """Break a 16-bit HEX_LO word into 4 nibbles and show as [H3 H2 H1 H0]."""
    h3 = (val16 >> 12) & 0xF
    h2 = (val16 >> 8) & 0xF
    h1 = (val16 >> 4) & 0xF
    h0 = val16 & 0xF
    return f"{h3:X} {h2:X} {h1:X} {h0:X}"

def decode_hex_up(val16):
    """Break HEX_UP into HEX5 and HEX4."""
    h5 = (val16 >> 4) & 0xF
    h4 = val16 & 0xF
    return f"{h5:X} {h4:X}"

def leds_str(val):
    """Show LED pattern as binary string, MSB=LED9."""
    return format(val & 0x3FF, "010b")


# ===========================================================================
# TEST SUITES
# ===========================================================================
passed = 0
failed = 0

def check(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {detail}")


def get_last_output(sim, port_name):
    """Return the last value written to a given port."""
    for cy, pn, val in reversed(sim.outputs):
        if pn == port_name:
            return val
    return None


# ---------------------------------------------------------------------------
# Test 1: Single-Ended Demo
# ---------------------------------------------------------------------------
def test_single_ended():
    print("\n=== Single-Ended Demo ===")
    mif = "C:/Users/User/Documents/School/ECE2031/adc-per/demos/single-ended.mif"

    # Test A: ADC reads 0x800 (2048), should scale to 0x80 (128) after >>4
    sim = SCOMP(mif)
    sim.set_channels({0: 2048})
    sim.run(max_cycles=500)

    hex_lo = get_last_output(sim, "HEX_LO")
    if hex_lo is not None:
        adc_displayed = hex_lo & 0xFF
        check("CH0=2048 -> displayed value is 0x80 (128)",
              adc_displayed == 0x80,
              f"got 0x{adc_displayed:02X}")
    else:
        check("HEX_LO was written", False, "no output")

    # Test B: ADC reads 0 -> display 0x00
    sim = SCOMP(mif)
    sim.set_channels({0: 0})
    sim.run(max_cycles=500)
    hex_lo = get_last_output(sim, "HEX_LO")
    if hex_lo is not None:
        adc_displayed = hex_lo & 0xFF
        check("CH0=0 -> displayed value is 0x00",
              adc_displayed == 0x00,
              f"got 0x{adc_displayed:02X}")

    # Test C: ADC reads 4095 -> display 0xFF
    sim = SCOMP(mif)
    sim.set_channels({0: 4095})
    sim.run(max_cycles=500)
    hex_lo = get_last_output(sim, "HEX_LO")
    if hex_lo is not None:
        adc_displayed = hex_lo & 0xFF
        check("CH0=4095 -> displayed value is 0xFF",
              adc_displayed == 0xFF,
              f"got 0x{adc_displayed:02X}")

    # Test D: When ADC value is far from target, no point is scored.
    # Initial target = timer & 0xFF = 0, so use a far-away ADC value.
    sim = SCOMP(mif)
    sim.set_channels({0: 2048})  # ADC>>4 = 128, target=0, |128-0|>8 -> miss
    sim.run(max_cycles=500)
    hex_up = get_last_output(sim, "HEX_UP")
    if hex_up is not None:
        check("Score stays 0 when ADC value far from target",
              hex_up == 0,
              f"got 0x{hex_up:04X}")


# ---------------------------------------------------------------------------
# Test 2: Differential Demo
# ---------------------------------------------------------------------------
def test_differential():
    print("\n=== Differential Demo ===")
    mif = "C:/Users/User/Documents/School/ECE2031/adc-per/demos/differential.mif"

    def run_diff(ch0, ch2, label):
        sim = SCOMP(mif)
        sim.set_channels({0: ch0, 2: ch2})
        sim.run(max_cycles=20000)
        hex_lo = get_last_output(sim, "HEX_LO")
        hex_up = get_last_output(sim, "HEX_UP")
        return sim, hex_lo, hex_up

    def extract_temp(hex_lo):
        """Extract temperature from 0x0TUC display word."""
        tens = (hex_lo >> 8) & 0xF
        units = (hex_lo >> 4) & 0xF
        c_char = hex_lo & 0xF
        return tens * 10 + units, c_char

    # Test A: Equal voltages -> 0 C
    sim, hex_lo, hex_up = run_diff(1000, 1000, "equal")
    if hex_lo is not None:
        temp, c = extract_temp(hex_lo)
        check("CH0=CH2=1000 -> 0 C",
              temp == 0 and c == 0xC,
              f"got {temp} C, suffix=0x{c:X}, HEX_LO=0x{hex_lo:04X}")

    # Test B: CH0=2050, CH2=1000 -> diff=1050, 1050/41=25 C
    sim, hex_lo, hex_up = run_diff(2050, 1000, "25C")
    if hex_lo is not None:
        temp, c = extract_temp(hex_lo)
        check("CH0=2050, CH2=1000 -> 25 C (diff=1050, 1050/41=25)",
              temp == 25 and c == 0xC,
              f"got {temp} C, HEX_LO=0x{hex_lo:04X}")

    # Test C: CH0=0, CH2=2000 -> negative diff -> clamped to 0 C
    sim, hex_lo, hex_up = run_diff(0, 2000, "negative")
    if hex_lo is not None:
        temp, c = extract_temp(hex_lo)
        check("CH0=0, CH2=2000 -> clamped to 0 C",
              temp == 0 and c == 0xC,
              f"got {temp} C, HEX_LO=0x{hex_lo:04X}")

    # Test D: CH0=4095, CH2=0 -> diff=4095, 4095/41=99 C (clamped)
    sim, hex_lo, hex_up = run_diff(4095, 0, "max")
    if hex_lo is not None:
        temp, c = extract_temp(hex_lo)
        check("CH0=4095, CH2=0 -> clamped to 99 C",
              temp == 99 and c == 0xC,
              f"got {temp} C, HEX_LO=0x{hex_lo:04X}")

    # Test E: CH0=3000, CH2=1000 -> diff=2000, 2000/41=48 C
    sim, hex_lo, hex_up = run_diff(3000, 1000, "48C")
    if hex_lo is not None:
        temp, c = extract_temp(hex_lo)
        expected = 2000 // 41  # = 48
        check(f"CH0=3000, CH2=1000 -> {expected} C (diff=2000)",
              temp == expected and c == 0xC,
              f"got {temp} C, HEX_LO=0x{hex_lo:04X}")

    # Test F: HEX_UP shows raw low byte
    sim, hex_lo, hex_up = run_diff(2050, 1000, "raw")
    if hex_up is not None:
        raw_diff = 2050 - 1000  # = 1050 = 0x041A
        expected_up = raw_diff & 0xFF  # = 0x1A = 26
        check(f"HEX_UP shows raw ADC low byte (diff=1050 -> 0x{expected_up:02X})",
              hex_up == expected_up,
              f"got 0x{hex_up:02X}")

    # Test G: Verify config word targets CH2 not CH1
    sim = SCOMP(mif)
    sim.set_channels({0: 3000, 1: 500, 2: 1000})
    sim.run(max_cycles=20000)
    hex_lo = get_last_output(sim, "HEX_LO")
    if hex_lo is not None:
        temp, c = extract_temp(hex_lo)
        expected = (3000 - 1000) // 41  # = 48 (uses CH2, not CH1)
        wrong = (3000 - 500) // 41      # = 60 (would get this if using CH1)
        check(f"Uses CH2 not CH1 (expect {expected} C, CH1 would give {wrong} C)",
              temp == expected,
              f"got {temp} C")


# ---------------------------------------------------------------------------
# Test 3: TTL Debug Demo
# ---------------------------------------------------------------------------
def test_ttl_debug():
    print("\n=== TTL Debug Demo ===")
    mif = "C:/Users/User/Documents/School/ECE2031/adc-per/demos/ttl-debug.mif"

    def run_ttl(ch0_mv, label):
        sim = SCOMP(mif)
        sim.set_channels({0: ch0_mv})
        sim.run(max_cycles=500)
        leds = get_last_output(sim, "LEDS")
        hex_up = get_last_output(sim, "HEX_UP")
        hex_lo = get_last_output(sim, "HEX_LO")
        return leds, hex_up, hex_lo

    # Test A: 300 mV -> LOW (V < 800)
    leds, hex_up, hex_lo = run_ttl(300, "low")
    check("300 mV -> LOW: bottom 5 LEDs (0b0000011111)",
          leds == 0x1F,
          f"got LEDs={leds_str(leds) if leds else 'None'}")
    check("300 mV -> HEX5='0' (state=LOW)",
          hex_up == 0x00,
          f"got HEX_UP=0x{hex_up:02X}" if hex_up is not None else "no output")
    if hex_lo is not None:
        margin = 800 - 300  # = 500 = 0x01F4
        check(f"300 mV -> margin = {margin} (0x{margin:04X})",
              hex_lo == margin,
              f"got HEX_LO=0x{hex_lo:04X}")

    # Test B: 1200 mV -> UNDEFINED (800 <= V <= 2000)
    leds, hex_up, hex_lo = run_ttl(1200, "undef")
    check("1200 mV -> UNDEF: all 10 LEDs (0b1111111111)",
          leds == 0x3FF,
          f"got LEDs={leds_str(leds) if leds else 'None'}")
    check("1200 mV -> HEX5='1' (state=UNDEF)",
          hex_up == 0x10,
          f"got HEX_UP=0x{hex_up:02X}" if hex_up is not None else "no output")
    if hex_lo is not None:
        depth = 1200 - 800  # = 400
        check(f"1200 mV -> depth past V_IL = {depth} (0x{depth:04X})",
              hex_lo == depth,
              f"got HEX_LO=0x{hex_lo:04X}")

    # Test C: 3300 mV -> HIGH (V > 2000)
    leds, hex_up, hex_lo = run_ttl(3300, "high")
    check("3300 mV -> HIGH: top 5 LEDs (0b1111100000)",
          leds == 0x3E0,
          f"got LEDs={leds_str(leds) if leds else 'None'}")
    check("3300 mV -> HEX5='2' (state=HIGH)",
          hex_up == 0x20,
          f"got HEX_UP=0x{hex_up:02X}" if hex_up is not None else "no output")
    if hex_lo is not None:
        margin = 3300 - 2000  # = 1300 = 0x0514
        check(f"3300 mV -> margin above V_IH = {margin} (0x{margin:04X})",
              hex_lo == margin,
              f"got HEX_LO=0x{hex_lo:04X}")

    # Test D: Exactly 800 mV -> UNDEF (not LOW, since V-800 = 0, JNEG not taken)
    leds, hex_up, hex_lo = run_ttl(800, "boundary_low")
    check("800 mV -> UNDEF (V-800=0, JNEG not taken)",
          hex_up == 0x10,
          f"got HEX_UP=0x{hex_up:02X}" if hex_up is not None else "no output")

    # Test E: Exactly 2000 mV -> UNDEF (V-2000=0, JPOS not taken)
    leds, hex_up, hex_lo = run_ttl(2000, "boundary_high")
    check("2000 mV -> UNDEF (V-2000=0, JPOS not taken)",
          hex_up == 0x10,
          f"got HEX_UP=0x{hex_up:02X}" if hex_up is not None else "no output")

    # Test F: 0 mV -> LOW with margin 800
    leds, hex_up, hex_lo = run_ttl(0, "zero")
    if hex_lo is not None:
        check("0 mV -> margin = 800 (0x0320)",
              hex_lo == 800,
              f"got HEX_LO=0x{hex_lo:04X}")

    # Test G: 4095 mV -> HIGH with margin 2095
    leds, hex_up, hex_lo = run_ttl(4095, "max")
    if hex_lo is not None:
        margin = 4095 - 2000
        check(f"4095 mV -> margin = {margin} (0x{margin:04X})",
              hex_lo == margin,
              f"got HEX_LO=0x{hex_lo:04X}")


# ===========================================================================
# Run all tests
# ===========================================================================
if __name__ == "__main__":
    print("SCOMP ADC Demo Test Suite")
    print("=" * 50)

    test_single_ended()
    test_differential()
    test_ttl_debug()

    print("\n" + "=" * 50)
    print(f"Results: {passed} passed, {failed} failed, {passed + failed} total")
    if failed:
        sys.exit(1)
    else:
        print("All tests passed!")
