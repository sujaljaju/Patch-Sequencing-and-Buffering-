import serial
import struct
import time

# --- Protocol Command Definitions ---
CMD_START = b'\x53'  # Hex 0x53 ('S')
CMD_END   = b'\x45'  # Hex 0x45 ('E')
ACK_READY = b'\x52'  # Hex 0x52 ('R')
ACK_END   = b'\x41'  # Hex 0x41 ('A')

def main():
    print("--- FPGA UART Data Sender (Handshake Edition) ---")
    
    # Get the COM port from the user
    com_port = input("Enter your COM port: ").strip()
    
    # Get the number of inputs to send
    try:
        # Limited to 255 words so the length fits in a single byte during the handshake
        num_words = int(input("How many 32-bit integers do you want to send? (Max 255): "))
        if num_words < 1 or num_words > 255:
            print("Please enter a number between 1 and 255.")
            return
    except ValueError:
        print("Invalid number entered. Exiting.")
        return

    # Collect the numbers from the user
    integers_to_send = []
    print(f"\nEnter your {num_words} integers.")
    print("(Note: You can type normal decimal numbers or use '0x' for Hexadecimal, e.g., 0x11223344)")
    
    for i in range(num_words):
        while True:
            user_input = input(f"Input {i}: ").strip()
            try:
                num = int(user_input, 0)
                if num < 0 or num > 0xFFFFFFFF:
                    print("  -> Error: Number is too large for 32-bit! Must be between 0 and 0xFFFFFFFF.")
                    continue
                integers_to_send.append(num)
                break
            except ValueError:
                print("  -> Error: Invalid format. Please try again.")

    print(f"\nConnecting to {com_port} at 921600 baud...")
    try:
        # Open serial port. Added a 5-second timeout for reading acknowledgments.
        ser = serial.Serial(com_port, 921600, timeout=5)
    
    
        
        # A tiny sleep to let the port initialize properly before sending data
        time.sleep(1) 
        
        # ---------------------------------------------------------
        # PHASE 1: CONNECTION ESTABLISHMENT
        # ---------------------------------------------------------
        print("\n[Handshake] Sending START command and word count...")
        ser.write(CMD_START)
        
        # Pack the integer length as a single unsigned byte ('>B')
        ser.write(struct.pack('>B', num_words))
        
        print("[Handshake] Waiting for READY acknowledgment from FPGA...")
        ready_response = ser.read(1) # Blocks until 1 byte is received or timeout occurs
        
        if ready_response != ACK_READY:
            print(f"Error: Did not receive READY. Received: {ready_response}. Check FPGA connection/logic.")
            ser.close()
            return
            
        print("[Handshake] READY received! FPGA is listening.")

        # ---------------------------------------------------------
        # PHASE 2: BULK TRANSMISSION
        # ---------------------------------------------------------
        print("\n[Data Transfer] Sending payload...")
        for i, num in enumerate(integers_to_send):
            # Pack the integer as a 4-byte big-endian binary struct ('>I')
            byte_data = struct.pack('>I', num) 
            ser.write(byte_data)
            print(f"Sent Address {i}: 0x{num:08X} (Decimal: {num})")
            
            # NOTE: time.sleep(0.05) has been removed. The CPU will now stream 
            # data at maximum UART speed since the handshake guarantees readiness.

        # ---------------------------------------------------------
        # PHASE 3: GRACEFUL TERMINATION
        # ---------------------------------------------------------
        print("\n[Handshake] Payload sent. Sending END command...")
        ser.write(CMD_END)
        
        print("[Handshake] Waiting for END acknowledgment from FPGA...")
        end_response = ser.read(1)
        
        if end_response != ACK_END:
            print(f"Error: Did not receive END ACK. Received: {end_response}.")
        else:
            print("[Handshake] END ACK received! Communication successfully terminated.")
            
        ser.close()
        print("\nSuccess: All data transmitted and port closed.")
        
    except serial.SerialException as e:
        print(f"\nSerial Port Error: {e}")
        print("Make sure the COM port is correct and not being used by another program (like Vivado/Putty).")

if __name__ == "__main__":
    main()