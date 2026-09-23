import serial
import struct
import time
import csv
import os

# --- Protocol Command Definitions ---
CMD_START     = b'\x53'  # Hex 0x53 ('S')
ACK_READY     = b'\x52'  # Hex 0x52 ('R')
ACK_END       = b'\x51'  # Hex 0x51 ('Q')
ACK_NEW_DATA  = b'\x50'  # Hex 0x50 ('P')

# Maps a received byte back to its symbolic protocol name, for console output.
ACK_NAMES = {
    CMD_START:    "CMD_START",
    ACK_READY:    "ACK_READY",
    ACK_END:      "ACK_END",
    ACK_NEW_DATA: "ACK_NEW_DATA",
}


def describe_ack(byte_val):
    """Return the symbolic protocol name for a byte the FPGA sent us, so the
    console shows 'ACK_READY' rather than the raw hex code. Falls back to a
    hex dump for anything unrecognized, and flags an empty read (timeout)."""
    if not byte_val:
        return "<no byte received -- timeout>"
    if byte_val in ACK_NAMES:
        return ACK_NAMES[byte_val]
    return f"UNKNOWN (0x{byte_val[0]:02X})"


# --- Data Source Configuration ---
#CSV_FILE_PATH = r"C:\Users\ASUS\Documents\major_project\one_to_one_buffer\gca_560_words.csv"   
CSV_FILE_PATH = r"C:\Users\ASUS\Documents\major_project\one_to_one_buffer\dummy_csv.csv" 
POINTER_FILE  = r"C:\Users\ASUS\Documents\major_project\one_to_one_buffer\pointer.txt"  # <-- tracks how far we've read into the CSV
MAX_WORDS_PER_BATCH = 80


def save_pointer(pointer_file, index):
    """Persist how far we've read, keeping a history of all pointer values."""
    with open(pointer_file, 'a') as f:  # Changed 'w' to 'a' (append)
        f.write(f"{index}\n")           # Added \n so values stack vertically


def load_pointer(pointer_file):
    """Return the row index to resume from by reading the *last* saved pointer."""
    if not os.path.exists(pointer_file):
        return 0
    try:
        with open(pointer_file, 'r') as f:
            lines = f.readlines()
            if not lines:
                return 0
            
            # Grab the last line that isn't just empty whitespace
            last_line = lines[-1].strip()
            return int(last_line) if last_line else 0
            
    except ValueError:
        print("Warning: pointer file was corrupt/unreadable. Resetting to 0.")
        return 0


def read_batch_from_csv(csv_path, start_index, max_count=MAX_WORDS_PER_BATCH):
    """
    Reads up to `max_count` integers from the CSV, starting at `start_index`.
    Expects one value per row (first column). Accepts decimal or 0x-hex.
    Returns (batch_list, new_index).
    """
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"CSV file not found: {csv_path}")

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = [row for row in reader if row and row[0].strip() != ""]

    total_rows = len(rows)
    if start_index >= total_rows:
        return [], start_index  

    end_index = min(start_index + max_count, total_rows)
    batch = []
    for row_num, row in enumerate(rows[start_index:end_index], start=start_index):
        val_str = row[0].strip()
        try:
            num = int(val_str, 0)  
        except ValueError:
            raise ValueError(f"Row {row_num}: '{val_str}' is not a valid integer.")
        if num < 0 or num > 0xFFFFFFFF:
            raise ValueError(f"Row {row_num}: value {val_str} out of 32-bit range.")
        batch.append(num)

    return batch, end_index


POLL_INTERVAL_SEC = 2  # how often to re-check the CSV when no new data is found


def send_one_batch(ser):

    start_index = load_pointer(POINTER_FILE)
    integers_to_send, next_index = read_batch_from_csv(CSV_FILE_PATH, start_index, MAX_WORDS_PER_BATCH)

    if not integers_to_send:
        return False  

    new_data_response = ser.read(1)
    nd_hex = f" (0x{new_data_response[0]:02X})" if new_data_response else ""
    print(f" FPGA sent: {describe_ack(new_data_response)}{nd_hex}")

    if new_data_response != ACK_NEW_DATA:
        raise RuntimeError(f"Did not receive NEW DATA ACK. Received: {describe_ack(new_data_response)}.")
    print("[Handshake] NEW DATA ACK received! FPGA is ready for data transfer.")

    num_words = len(integers_to_send)
    print(f"\nLoaded {num_words} value(s) from CSV (rows {start_index} to {next_index - 1}).")

    # Pack the integer count as a single unsigned byte ('>B')
    ser.write(struct.pack('>B', num_words))
    print(f"Sent word count: {num_words} (0x{num_words:02X})")

    print("[Data Transfer] Sending payload...")
    for i, num in enumerate(integers_to_send):
        byte_data = struct.pack('>I', num)  # 4-byte big-endian
        ser.write(byte_data)
        print(f"Sent Word {i}: 0x{num:08X} (Decimal: {num})")

    end_response = ser.read(1)
    end_hex = f" (0x{end_response[0]:02X})" if end_response else ""
    print(f" FPGA sent: {describe_ack(end_response)}{end_hex}")

    if end_response != ACK_END:
        raise RuntimeError(f"Did not receive END ACK. Received: {describe_ack(end_response)}. Batch will be retried.")

    print("END ACK received! Batch transfer complete.")
    save_pointer(POINTER_FILE, next_index)
    print(f"Pointer advanced to row {next_index}.")
    return True


def main():
    print("--- FPGA UART Data Sender ---")
    com_port = input("Enter your COM port: ").strip()

    try:
        ser = serial.Serial(com_port, 921600, timeout=5)
        time.sleep(1)

        print(f"\nSending START command: 0x{CMD_START[0]:02X} (CMD_START)")
        ser.write(CMD_START)

        print("Waiting for READY acknowledgment from FPGA...")
        ready_response = ser.read(1)

        hex_val = f" (0x{ready_response[0]:02X})" if ready_response else ""
        print(f"FPGA sent: {describe_ack(ready_response)}{hex_val}")

        if ready_response != ACK_READY:
            print(f"Error: Did not receive READY. Received: {describe_ack(ready_response)}. Check FPGA connection/logic.")
            ser.close()
            return
        else:
            print("READY received. FPGA is ready for data transfer.\n")
        print(" READY received. Initialization complete.\n")

    except serial.SerialException as e:
        print(f"\nSerial Port Error: {e}")
        print("Make sure the COM port is correct.")
        return

    print("Entering continuous send loop. Press Ctrl+C to stop.\n")
    try:
        while True:
            try:
                sent = send_one_batch(ser)
                if not sent:
                    print(f"No new data yet. Re-checking CSV in {POLL_INTERVAL_SEC}s...")
                    time.sleep(POLL_INTERVAL_SEC)
            except (FileNotFoundError, ValueError) as e:
                print(f"CSV error: {e}. Retrying in {POLL_INTERVAL_SEC}s...")
                time.sleep(POLL_INTERVAL_SEC)
            except RuntimeError as e:
                print(f"Protocol error: {e}")
                print(f"Retrying in {POLL_INTERVAL_SEC}s...")
                time.sleep(POLL_INTERVAL_SEC)
    except KeyboardInterrupt:
        print("\nStopped by user (Ctrl+C).")
    except serial.SerialException as e:
        print(f"\nSerial Port Error: {e}")
    finally:
        ser.close()
        print("Port closed.")


if __name__ == "__main__":
    main()