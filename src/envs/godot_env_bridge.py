#!/usr/bin/env python3
"""Low-latency synchronous TCP IPC bridge between Python and Godot 4 RL environments.

Uses 4-byte big-endian length-prefixed JSON frames for zero-dependency, sub-millisecond
lockstep stepping and deterministic reset cycles.
"""

from __future__ import annotations

import atexit
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_GODOT_PATH = r"C:\Users\TDV\Downloads\Godot4\Godot_v4.7.2-stable_win64_console.exe"


def find_godot_binary() -> str:
    """Locate the Godot 4 executable path."""
    if "GODOT_BIN" in os.environ and os.path.isfile(os.environ["GODOT_BIN"]):
        return os.environ["GODOT_BIN"]
    if os.path.isfile(DEFAULT_GODOT_PATH):
        return DEFAULT_GODOT_PATH
    system_godot = shutil.which("godot") or shutil.which("godot4")
    if system_godot:
        return system_godot
    raise FileNotFoundError(
        f"Godot binary not found at '{DEFAULT_GODOT_PATH}' and not in PATH. "
        "Set GODOT_BIN environment variable."
    )


class GodotTCPClient:
    """Synchronous socket client talking to TrainingEnvBase in Godot."""

    def __init__(self, host: str = "127.0.0.1", port: int = 11000, timeout: float = 20.0) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self.sock: Optional[socket.socket] = None

    def connect(self, retry_interval: float = 0.2) -> None:
        """Connect to Godot TCP server with timeout retry."""
        deadline = time.time() + self.timeout
        last_err = None
        while time.time() < deadline:
            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                s.settimeout(self.timeout)
                s.connect((self.host, self.port))
                self.sock = s
                return
            except (ConnectionRefusedError, OSError) as e:
                last_err = e
                time.sleep(retry_interval)
        raise TimeoutError(f"Failed to connect to Godot on {self.host}:{self.port} within {self.timeout}s: {last_err}")

    def send_message(self, data: Dict[str, Any]) -> None:
        """Send 4-byte length-prefixed JSON message."""
        if not self.sock:
            raise ConnectionError("Socket not connected.")
        json_bytes = json.dumps(data).encode("utf-8")
        header = struct.pack("!I", len(json_bytes))
        self.sock.sendall(header + json_bytes)

    def receive_message(self) -> Dict[str, Any]:
        """Receive 4-byte length-prefixed JSON message."""
        if not self.sock:
            raise ConnectionError("Socket not connected.")

        # Read 4-byte length header
        header_data = bytearray()
        while len(header_data) < 4:
            chunk = self.sock.recv(4 - len(header_data))
            if not chunk:
                raise ConnectionResetError("Godot closed the connection while reading header.")
            header_data.extend(chunk)

        payload_len = struct.unpack("!I", header_data)[0]

        # Read payload
        payload_data = bytearray()
        while len(payload_data) < payload_len:
            chunk = self.sock.recv(payload_len - len(payload_data))
            if not chunk:
                raise ConnectionResetError("Godot closed the connection while reading payload.")
            payload_data.extend(chunk)

        return json.loads(payload_data.decode("utf-8"))

    def reset(self, seed: int = 0, difficulty: float = 0.0) -> Tuple[List[float], Dict[str, Any]]:
        """Send reset command and receive initial observation."""
        self.send_message({"command": "reset", "seed": seed, "difficulty": difficulty})
        res = self.receive_message()
        obs = res.get("observation", [])
        info = res.get("info", {})
        return obs, info

    def step(self, action: List[float]) -> Tuple[List[float], float, bool, bool, Dict[str, Any]]:
        """Send action and receive step result."""
        self.send_message({"command": "step", "action": action})
        res = self.receive_message()
        obs = res.get("observation", [])
        reward = float(res.get("reward", 0.0))
        terminated = bool(res.get("terminated", False))
        truncated = bool(res.get("truncated", False))
        info = res.get("info", {})
        return obs, reward, terminated, truncated, info

    def close(self) -> None:
        """Close connection gracefully."""
        if self.sock:
            try:
                self.send_message({"command": "close"})
            except Exception:
                pass
            try:
                self.sock.close()
            except Exception:
                pass
            self.sock = None


class GodotEnvBridge:
    """Manages Godot headless subprocess lifecycle and TCP client connection."""

    def __init__(
        self,
        scene_path: str,
        port: int = 11000,
        godot_bin: Optional[str] = None,
        ticks_per_step: int = 4,
        headless: bool = True,
        autostart: bool = True,
    ) -> None:
        self.scene_path = scene_path
        self.port = port
        self.godot_bin = godot_bin or find_godot_binary()
        self.ticks_per_step = ticks_per_step
        self.headless = headless
        self.process: Optional[subprocess.Popen] = None
        self.client: Optional[GodotTCPClient] = None

        # Resolve godot project directory
        proj_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        self.godot_project_path = os.path.join(proj_root, "godot")

        atexit.register(self.close)

        if autostart:
            self.start()
        else:
            self.connect_existing()

    def connect_existing(self, timeout: float = 25.0) -> None:
        """Connect to an externally running Godot instance (e.g., Godot Editor F6)."""
        self.client = GodotTCPClient(host="127.0.0.1", port=self.port, timeout=timeout)
        try:
            self.client.connect()
        except Exception as e:
            self.close()
            raise RuntimeError(f"Failed to connect to running Godot instance on port {self.port}: {e}")

    def start(self) -> None:
        """Spawn Godot process and connect TCP client."""
        cmd = [
            self.godot_bin,
            "--path",
            self.godot_project_path,
            self.scene_path,
            f"--port={self.port}",
            f"--ticks={self.ticks_per_step}",
            "--fixed-fps",
            "60",
            "--max-fps",
            "0",
            "--disable-vsync",
        ]
        if self.headless:
            cmd.insert(1, "--headless")

        # Start Godot detached from console
        self.process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        # Connect TCP client
        self.client = GodotTCPClient(host="127.0.0.1", port=self.port, timeout=25.0)
        try:
            self.client.connect()
        except Exception as e:
            self.close()
            raise RuntimeError(f"Failed to connect to Godot on port {self.port}: {e}")

    def reset(self, seed: int = 0, difficulty: float = 0.0) -> Tuple[List[float], Dict[str, Any]]:
        if not self.client:
            raise RuntimeError("Bridge not started.")
        return self.client.reset(seed, difficulty)

    def step(self, action: List[float]) -> Tuple[List[float], float, bool, bool, Dict[str, Any]]:
        if not self.client:
            raise RuntimeError("Bridge not started.")
        return self.client.step(action)

    def close(self) -> None:
        """Terminate Godot process and close client."""
        if self.client:
            self.client.close()
            self.client = None
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=2.0)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass
            self.process = None
