#!/usr/bin/env python3
"""Godot 4 3D Digital Twin WebSocket Bridge Server.

Connects the PortEnv reinforcement learning environment with the Godot 3D engine.
Streams live simulation telemetry, yard matrix occupancy, and crane states over WebSockets.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import hashlib
import json
import os
import struct
import sys
from typing import Any, Dict, Optional, Set

# Ensure project root is in sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from src.port_sim.config import default_config, medium_config
from src.port_sim.env import PortEnv
from src.port_sim.models import ContainerType


class MinimalWebSocketServer:
    """Zero-dependency RFC 6455 WebSocket Server using asyncio."""

    def __init__(self, host: str = "127.0.0.1", port: int = 9090) -> None:
        self.host = host
        self.port = port
        self.clients: Set[asyncio.StreamWriter] = set()
        self.message_handler: Optional[Any] = None

    async def start(self) -> None:
        server = await asyncio.start_server(self._handle_client, self.host, self.port)
        print(f"[*] Godot Bridge WebSocket Server listening on ws://{self.host}:{self.port}")
        async with server:
            await server.serve_forever()

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        # Handshake
        request = await reader.read(4096)
        req_str = request.decode("utf-8", errors="ignore")
        headers = {}
        for line in req_str.split("\r\n")[1:]:
            if ": " in line:
                k, v = line.split(": ", 1)
                headers[k.lower()] = v.strip()

        key = headers.get("sec-websocket-key")
        if not key:
            writer.close()
            await writer.wait_closed()
            return

        # Compute accept key
        guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        accept = base64.b64encode(hashlib.sha1((key + guid).encode("utf-8")).digest()).decode("utf-8")

        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        writer.write(response.encode("utf-8"))
        await writer.drain()

        self.clients.add(writer)
        print(f"[+] Godot Digital Twin client connected from {writer.get_extra_info('peername')}")

        try:
            # Inform handler of new connection
            if self.message_handler:
                await self.message_handler({"command": "init"}, writer)

            while not reader.at_eof():
                header = await reader.read(2)
                if len(header) < 2:
                    break
                b1, b2 = header
                opcode = b1 & 0x0F
                if opcode == 0x08:  # Close
                    break

                masked = bool(b2 & 0x80)
                length = b2 & 0x7F
                if length == 126:
                    ext = await reader.read(2)
                    length = struct.unpack("!H", ext)[0]
                elif length == 127:
                    ext = await reader.read(8)
                    length = struct.unpack("!Q", ext)[0]

                masks = await reader.read(4) if masked else b""
                data = await reader.read(length)
                if masked:
                    data = bytes(b ^ masks[i % 4] for i, b in enumerate(data))

                if opcode == 0x01:  # Text frame
                    msg_text = data.decode("utf-8")
                    if self.message_handler:
                        try:
                            msg_dict = json.loads(msg_text)
                            await self.message_handler(msg_dict, writer)
                        except Exception as e:
                            print(f"[!] Error parsing message: {e}")

        except Exception as e:
            print(f"[!] Client error: {e}")
        finally:
            self.clients.discard(writer)
            writer.close()
            await writer.wait_closed()
            print("[-] Godot Digital Twin client disconnected")

    async def broadcast(self, data: Dict[str, Any]) -> None:
        if not self.clients:
            return
        json_bytes = json.dumps(data).encode("utf-8")
        frame = self._encode_frame(json_bytes)
        for client in list(self.clients):
            try:
                client.write(frame)
                await client.drain()
            except Exception:
                self.clients.discard(client)

    async def send_to(self, writer: asyncio.StreamWriter, data: Dict[str, Any]) -> None:
        try:
            json_bytes = json.dumps(data).encode("utf-8")
            writer.write(self._encode_frame(json_bytes))
            await writer.drain()
        except Exception:
            self.clients.discard(writer)

    def _encode_frame(self, data: bytes) -> bytes:
        length = len(data)
        if length <= 125:
            header = struct.pack("!BB", 0x81, length)
        elif length <= 65535:
            header = struct.pack("!BBH", 0x81, 126, length)
        else:
            header = struct.pack("!BBQ", 0x81, 127, length)
        return header + data


class PortEnvGodotBridge:
    """Manages the environment simulation lifecycle and serializes state for Godot."""

    def __init__(self, scenario: str = "default") -> None:
        self.config = medium_config() if scenario == "medium" else default_config()
        self.env = PortEnv(self.config)
        self.obs, self.info = self.env.reset(seed=42)
        self.step_count = 0
        self.accum_reward = 0.0
        self.is_auto_running = False

    def reset_env(self) -> Dict[str, Any]:
        self.obs, self.info = self.env.reset()
        self.step_count = 0
        self.accum_reward = 0.0
        return self.get_state_snapshot("Environment reset to initial state.")

    def step_env(self, action: Optional[int] = None) -> Dict[str, Any]:
        if action is None:
            # Fallback heuristic: find the first stack with space
            action = self.env.action_space.sample()

        obs, reward, terminated, truncated, info = self.env.step(action)
        self.obs, self.info = obs, info
        self.step_count += 1
        self.accum_reward += reward

        event_msg = f"Step {self.step_count}: Action {action} -> Reward {reward:+.2f}"
        if terminated or truncated:
            event_msg += " (Episode Complete)"

        return self.get_state_snapshot(event_msg, reward=reward)

    def get_state_snapshot(self, event: str = "", reward: float = 0.0) -> Dict[str, Any]:
        # Serialize 4D yard grid matching Yard(blocks, bays, stacks, tiers)
        yard = self.env.yard
        grid_4d = []
        for b in range(yard.blocks):
            block_arr = []
            for bay in range(yard.bays):
                bay_arr = []
                for s in range(yard.stacks):
                    stack_arr = []
                    for t in range(yard.tiers):
                        cid = int(yard._grid[b, bay, s, t])
                        if cid != 0 and cid in yard._containers:
                            c = yard._containers[cid]
                            c_type = int(c.type.value) if hasattr(c.type, "value") else int(c.type)
                            stack_arr.append({"id": cid, "type": c_type})
                        else:
                            stack_arr.append(None)
                    bay_arr.append(stack_arr)
                block_arr.append(bay_arr)
            grid_4d.append(block_arr)

        return {
            "step": self.step_count,
            "sim_time": self.env.sim_time,
            "reward": reward,
            "accum_reward": self.accum_reward,
            "yard_grid": grid_4d,
            "event": event,
            "active_ships": len(self.env.scheduler.active_ships),
            "pending_containers": len(self.env.scheduler.pending_containers),
        }


async def main() -> None:
    parser = argparse.ArgumentParser(description="Godot 4 3D Digital Twin WebSocket Bridge")
    parser.add_argument("--scenario", choices=["default", "medium"], default="default", help="PortEnv scenario")
    parser.add_argument("--host", default="127.0.0.1", help="WebSocket bind host")
    parser.add_argument("--port", type=int, default=9090, help="WebSocket bind port")
    args = parser.parse_args()

    bridge = PortEnvGodotBridge(args.scenario)
    server = MinimalWebSocketServer(args.host, args.port)

    async def handle_message(msg: Dict[str, Any], client_writer: Any) -> None:
        cmd = msg.get("command")
        if cmd == "init":
            await server.send_to(client_writer, bridge.get_state_snapshot("Connected to simulation."))
        elif cmd == "step":
            state = bridge.step_env()
            await server.broadcast(state)
        elif cmd == "reset":
            state = bridge.reset_env()
            await server.broadcast(state)
        elif cmd == "auto_run":
            bridge.is_auto_running = bool(msg.get("enabled", False))

    server.message_handler = handle_message

    async def auto_run_loop() -> None:
        while True:
            await asyncio.sleep(0.8)
            if bridge.is_auto_running and server.clients:
                state = bridge.step_env()
                await server.broadcast(state)

    asyncio.create_task(auto_run_loop())
    await server.start()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[*] Bridge server stopped.")
