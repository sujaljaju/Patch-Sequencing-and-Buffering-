import serial
import struct
import time

BAUD_RATE = 115200  # must match psa_new.v's uart_rx CLKS_PER_BIT (868 at 100MHz)


def get_values():
    print("Select input mode:")
    print("1. Enter custom values manually")
    print("2. Use default test pattern")
    choice = input("Choice (1 or 2, default 2): ").strip()

    if choice == '1':
        values = []
        try:
            n = int(input("How many 32-bit integers do you want to send? (max 80): "))
        except ValueError:
            print("Invalid number entered. Exiting.")
            return None
        if n < 1 or n > 80:
            print("Please enter a number between 1 and 80 (matches the FPGA's NUM_WORDS).")
            return None

        print(f"\nEnter your {n} integers (decimal, or 0x... for hex).")
        while len(values) < n:
            user_input = input(f"Input {len(values)}: ").strip()
            try:
                val = int(user_input, 0)
                if val < 0 or val > 0xFFFFFFFF:
                    print("  -> Error: must be between 0 and 0xFFFFFFFF. Try again.")
                    continue
                values.append(val)
            except ValueError:
                print("  -> Error: invalid format. Try again.")
        return values
    else:
        print("\nUsing default test pattern: 10 values.")
        return [v * 111 for v in range(1, 11)]


def main():
    print("--- FPGA UART Sender (RTS/CTS handshake) ---")
    com_port = input("Enter your COM port: ").strip()

    values = get_values()
    if values is None:
        return

    print(f"\nConnecting to {com_port} at {BAUD_RATE} baud...")
    try:
        # rtscts=False: we drive/read RTS and CTS manually below, not via
        # pyserial's automatic hardware flow control, so we stay in full
        # control of exactly when each transition happens.
        ser = serial.Serial(com_port, BAUD_RATE, timeout=5, rtscts=False)
        time.sleep(1)  # let the port settle before touching it

        # Make sure we start from a known idle state on our own RTS line
        ser.rts = False

        print("Waiting for FPGA to signal readiness (CTS)...")
        while ser.cts == False:
            time.sleep(0.001)
            print('FPGA NOT READY YET')
        print("FPGA is ready (CTS asserted). Sending payload...")

        for i, val in enumerate(values):
            packed = struct.pack('>I', val)  # Big-Endian, matches psa_new.v's byte assembly
            ser.write(packed)
            print(f"[{i+1}/{len(values)}] Sent: {val} (0x{val:08X})")

        # Make sure every byte has actually left the wire before we signal "done" --
        # write() only queues bytes; it does not block until they're transmitted.
        ser.flush()

        print("\nAll words transmitted. Asserting RTS (signalling 'done sending')...")
        ser.rts = True

        print("Waiting for FPGA to finish processing (CTS drops, then returns)...")
        # FPGA drops CTS while streaming/capturing the batch, then raises it
        # again once it's back in S_IDLE and ready for the next batch.
        while ser.cts == True:
            time.sleep(0.001)
        while ser.cts == False:
            time.sleep(0.001)

        ser.rts = False  # return the line to idle for the next batch
        print("Handshake complete. FPGA processed the batch and is ready again.")

        ser.close()
        print("Port closed.")
    
    except serial.SerialException as e:
        print(f"\nSerial Port Error: {e}")
        print("Check the COM port is correct and not already open elsewhere (Vivado/TeraTerm/PuTTY).")


if __name__ == "__main__":
    main()
