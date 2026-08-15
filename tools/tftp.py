import tftpy
import os
import logging

logging.basicConfig(level=logging.INFO)

root_dir = os.getcwd()
print(f"Start TFTP. Root path: {root_dir}")

server = tftpy.TftpServer(root_dir)

try:
	server.listen("0.0.0.0", 69)
except KeyboardInterrupt:
	print("\nStopped")

