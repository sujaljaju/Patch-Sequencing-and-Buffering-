import serial
import struct
import time

def main():
    print("--- FPGA UART Data Sender ---")
    
    # 1. Get the COM port from the user
    com_port = input("Enter your COM port (e.g., COM3 for Windows or /dev/ttyUSB0 for Linux): ").strip()
    
    # 2. Get the number of inputs to send
    try:
        num_words = int(input("How many 32-bit integers do you want to send? "))
    except ValueError:
        print("Invalid number entered. Exiting.")
        return

    # 3. Collect the numbers from the user
    integers_to_send = []
    print(f"\nEnter your {num_words} integers.")
    print("(Note: You can type normal decimal numbers or use '0x' for Hexadecimal, e.g., 0x11223344)")
    
    for i in range(num_words):
        while True:
            user_input = input(f"Input {i}: ").strip()
            try:
                # int(val, 0) automatically understands both decimal and '0x' hex prefixes
                num = int(user_input, 0)
                
                # Check if it fits in a 32-bit unsigned integer limit
                if num < 0 or num > 0xFFFFFFFF:
                    print("  -> Error: Number is too large for 32-bit! Must be between 0 and 0xFFFFFFFF.")
                    continue
                    
                integers_to_send.append(num)
                break
            except ValueError:
                print("  -> Error: Invalid format. Please try again.")

    # 4. Connect to UART and send the data
    print(f"\nConnecting to {com_port} at 9600 baud...")
    try:
        # Open serial port
        ser = serial.Serial(com_port, 9600, timeout=1)
        
        # A tiny sleep to let the port initialize properly
        time.sleep(1) 
        
        print("Sending data...")
        for i, num in enumerate(integers_to_send):
            # Pack the integer as a 4-byte big-endian binary struct ('>I')
            byte_data = struct.pack('>I', num) 
            ser.write(byte_data)
            
            print(f"Sent Address {i}: 0x{num:08X} (Decimal: {num})")
            
            # Very brief delay to ensure the FPGA buffer catches it smoothly
            time.sleep(0.05) 
            
        ser.close()
        print("\nSuccess: All data transmitted and port closed.")
        
    except serial.SerialException as e:
        print(f"\nSerial Port Error: {e}")
        print("Make sure the COM port is correct and not being used by another program (like Vivado/Putty).")

if __name__ == "__main__":
    main()