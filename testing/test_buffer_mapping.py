"""
Test the ADC.vhd round-robin buffer mapping against the LTC2308 pipeline delay.

Models the exact behavior of:
  1. ADC.vhd round-robin state machine (IDLE → CONVERTING → WAIT_BUSY → STORE)
  2. LTC2308 pipeline: the result received from SPI is from the config sent
     in the PREVIOUS frame, not the current one.

Each "frame" = one full cycle through CONVERTING → WAIT_BUSY → STORE.
The cfg_word sent to the LTC2308 during a frame determines what the ADC
converts, but the result is only available in the NEXT frame's SPI read.

We run enough frames to reach steady state (past the first garbage frame)
and then verify that buf_chN == CH_N for all N.
"""

import sys

# ---------------------------------------------------------------------------
# Model of the corrected STORE mapping from ADC.vhd
# ---------------------------------------------------------------------------
STORE_MAP_FIXED = {
    0: 7,  # ch_count=0 → buf_ch7
    1: 0,  # ch_count=1 → buf_ch0
    2: 1,  # ch_count=2 → buf_ch1
    3: 2,  # ch_count=3 → buf_ch2
    4: 3,  # ch_count=4 → buf_ch3
    5: 4,  # ch_count=5 → buf_ch4
    6: 5,  # ch_count=6 → buf_ch5
    7: 6,  # ch_count=7 → buf_ch6
}

# Original (broken) mapping for comparison
STORE_MAP_OLD = {
    0: 1,  # ch_count=0 → buf_ch1
    1: 0,  # ch_count=1 → buf_ch0
    2: 7,  # ch_count=2 → buf_ch7
    3: 6,  # ch_count=3 → buf_ch6
    4: 5,  # ch_count=4 → buf_ch5
    5: 4,  # ch_count=5 → buf_ch4
    6: 3,  # ch_count=6 → buf_ch3
    7: 2,  # ch_count=7 → buf_ch2
}

# cfg_word → channel mapping.
# The CASE (ch_count + 1) MOD 8 selects the config for the NEXT frame's SPI.
# (ch_count+1)%8 = N  → cfg_word for CH_N.
# So the config sent in the SPI of the frame at ch_count=N is the one set
# during the STORE of ch_count=(N-1+8)%8, which is for channel ((N-1+1)%8) = N.
# In short: frame at ch_count=N sends CH_N config over SPI.
# IDLE also pre-loads CH0 config.
FRAME_CONFIG_CHANNEL = {n: n for n in range(8)}  # frame N sends CH_N config


def simulate_roundrobin(store_map, num_rounds=3, verbose=False):
    """
    Simulate the round-robin and return the steady-state buffer contents.

    The LTC2308 pipeline means:
      result received in frame N = conversion from config sent in frame N-1.

    Returns: dict { buf_index: channel_data_it_contains }
    """
    buffers = [None] * 8          # buf_ch0..buf_ch7
    prev_config_channel = None    # config sent in the previous frame

    for rnd in range(num_rounds):
        for ch_count in range(8):
            # What config is sent this frame?
            config_ch = FRAME_CONFIG_CHANNEL[ch_count]

            # What result do we receive? (from previous frame's config)
            if prev_config_channel is not None:
                result_channel = prev_config_channel
            else:
                result_channel = "garbage"  # very first frame, no prior config

            # STORE: put the result into the mapped buffer
            buf_idx = store_map[ch_count]
            buffers[buf_idx] = result_channel

            if verbose:
                print(f"  round={rnd} ch_count={ch_count}: "
                      f"SPI sends CH{config_ch} config, "
                      f"receives {'CH'+str(result_channel) if isinstance(result_channel, int) else result_channel} data "
                      f"-> stored in buf_ch{buf_idx}")

            # Advance pipeline: this frame's config becomes "previous" for next frame
            prev_config_channel = config_ch

    return {i: buffers[i] for i in range(8)}


def test_mapping(name, store_map, verbose=False):
    print(f"\n{'='*60}")
    print(f"Testing: {name}")
    print(f"{'='*60}")

    if verbose:
        print("\nFrame-by-frame trace (3 full rounds):")
    result = simulate_roundrobin(store_map, num_rounds=3, verbose=verbose)

    print(f"\nSteady-state buffer contents:")
    all_correct = True
    for buf_idx in range(8):
        actual = result[buf_idx]
        expected = buf_idx
        ok = (actual == expected)
        status = "PASS" if ok else "FAIL"
        if not ok:
            all_correct = False
        print(f"  {status}  buf_ch{buf_idx} contains CH{actual} data"
              f"{'  (expected CH' + str(expected) + ')' if not ok else ''}")

    return all_correct


# ===========================================================================
# Run tests
# ===========================================================================
if __name__ == "__main__":
    print("ADC Round-Robin Buffer Mapping Verification")
    print("Modeling LTC2308 1-frame pipeline delay")

    # Test the OLD (broken) mapping
    old_ok = test_mapping("OLD mapping (before fix)", STORE_MAP_OLD, verbose=True)

    # Test the NEW (fixed) mapping
    new_ok = test_mapping("FIXED mapping (after fix)", STORE_MAP_FIXED, verbose=True)

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    print(f"  Old mapping:   {'all correct' if old_ok else 'HAS ERRORS'}")
    print(f"  Fixed mapping: {'all correct' if new_ok else 'HAS ERRORS'}")

    if not new_ok:
        print("\nFIXED MAPPING STILL HAS ERRORS -- investigate!")
        sys.exit(1)
    elif old_ok:
        print("\nOld mapping was already correct?? Re-check pipeline assumption.")
        sys.exit(1)
    else:
        print("\nFix verified: old mapping was broken, new mapping is correct.")
        sys.exit(0)
