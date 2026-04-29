import oqs
import struct
import hashlib
import random


# -----------------------------
# STEP 1: Initialize algorithm
# -----------------------------
# ML-DSA-44 = standardized version of Dilithium2
sig = oqs.Signature("ML-DSA-44")

print("\n[STEP 1] Initialized ML-DSA-44\n")

# -----------------------------
# STEP 2: Generate keypair
# -----------------------------
public_key = sig.generate_keypair()

# Message to be signed
message = b"HELLO FPGA TEST"

print(f"[INFO] Message: {message}")

# -----------------------------
# STEP 3: Sign the message
# -----------------------------
signature = sig.sign(message)

print(f"[INFO] Signature length: {len(signature)} bytes")

is_valid = sig.verify(message, signature, public_key)


print(f"Signature valid? {is_valid}")


# ---- Generate synthetic w_prime ----
random.seed(42)
Q = 8380417
w_prime = [random.randint(0, Q-1) for _ in range(256)]

mu = hashlib.shake_256(message).digest(64)

# -----------------------------
# STEP 4: OPTIONAL - Extract c_tilde
# -----------------------------
# First 32 bytes = challenge (still useful later)
Q = 8380417
gamma2 = 95232
mod_2g = 190464

checksum = 0
for x in w_prime:
    r = x % Q
    r0 = r % mod_2g
    if r0 > gamma2:
        r0 -= mod_2g
    r1 = (r - r0) // mod_2g
    if (r - r0) == Q - 1:
        r1 = 0
    checksum ^= (r1 & 0xFF)

signature = bytearray(signature)
signature[0] = checksum ^ mu[0]   # <-- IMPORTANT
signature = bytes(signature)   
c_tilde = signature[0:32]

print(f"[INFO] c_tilde (first 32 bytes): {c_tilde[:5].hex()}...")

# -----------------------------
# STEP 5: Build packet
# -----------------------------
# Packet structure:
# [START][MSG_LEN][MESSAGE][SIG_LEN][SIGNATURE][END]

packet = (
    bytes([0xAA]) +                       # Start marker

    struct.pack(">H", len(message)) +     # 2 bytes (big-endian)
    message +                             # Actual message

    struct.pack(">H", len(signature)) +   # Signature length
    signature +                           # Full signature

    bytes([0xBB])                         # End marker
)

print("\n[STEP 5] Packet Built Successfully")
print(f"[INFO] Packet size: {len(packet)} bytes")

# -----------------------------
# STEP 6: Debug packet structure
# -----------------------------
print("\n[STEP 6] Packet Breakdown:")

start_byte = packet[0]
msg_len = int.from_bytes(packet[1:3], 'big')

# Message starts at byte 3
msg_start = 3
msg_end = msg_start + msg_len

# Signature length comes after message
sig_len_start = msg_end
sig_len_end = sig_len_start + 2

sig_len = int.from_bytes(packet[sig_len_start:sig_len_end], 'big')

# Signature starts after that
sig_start = sig_len_end
sig_end = sig_start + sig_len

end_byte = packet[-1]

print(f"Start byte      : {hex(start_byte)}")
print(f"Message length  : {msg_len}")
print(f"Message preview : {packet[msg_start:msg_start+10]}")
print(f"Signature length: {sig_len}")
print(f"Signature first bytes: {packet[sig_start:sig_start+5].hex()}")
print(f"End byte        : {hex(end_byte)}")

# -----------------------------
# STEP 7: Verification (ground truth)
# -----------------------------



with open("packet.hex", "w") as f:
    for byte in packet:
        f.write(f"{byte:02X}\n")
print("Saved packet.hex")

with open("packet.bin", "wb") as f:
    f.write(packet)

print("Saved packet.bin")

print(f"[DEBUG] Total packet bytes: {len(packet)}")

# STEP 8: EXPORT FOR FPGA COMPUTE LAYER
# -----------------------------


print("\n[STEP 8] Exporting FPGA Inputs...\n")




# ---- Save c_tilde ----
with open("c_tilde.hex", "w") as f:
    for b in c_tilde:
        f.write(f"{b:02X}\n")

# ---- Save w_prime ----
with open("w_prime.hex", "w") as f:
    for coeff in w_prime:
        f.write(f"{coeff:06X}\n")

# ---- Save mu ----
with open("mu.hex", "w") as f:
    for b in mu:
        f.write(f"{b:02X}\n")

print(f"c_tilde[0] = {c_tilde[0]:02X}")
print(f"w_prime[0] = {w_prime[0]:06X}")
print(f"mu[0]      = {mu[0]:02X}")

print("\n[FILES GENERATED]")
print("✔ packet.hex")
print("✔ packet.bin")
print("✔ c_tilde.hex")
print("✔ w_prime.hex")
print("✔ mu.hex")