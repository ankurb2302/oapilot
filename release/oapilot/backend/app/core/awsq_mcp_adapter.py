"""Standalone MCP Configuration Manager for OAPilot

This module allows OAPilot to read and use AWS Q's MCP configuration format
without requiring AWS Q to be installed. OAPilot acts as a standalone
AI assistant that uses the same configuration format as AWS Q for compatibility.
"""

import json
import os
import subprocess
import asyncio
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Union
from dataclasses import dataclass
from enum import Enum

from app.core.config import settings
from app.core.mcp_client import MCPClient, MCPManager

logger = logging.getLogger(__name__)


class MCPTransportType(Enum):
    """MCP server transport types supported by AWS Q"""
    STDIO = "stdio"  # Local process communication via stdin/stdout
    HTTP = "http"    # Remote server via HTTP


@dataclass
class AWSQMCPServerConfig:
    """Configuration for an MCP server in AWS Q format"""
    name: str
    transport_type: MCPTransportType

    # For STDIO transport
    command: Optional[str] = None
    args: Optional[List[str]] = None
    env: Optional[Dict[str, str]] = None
    timeout: Optional[int] = 30000  # milliseconds

    # For HTTP transport
    url: Optional[str] = None
    headers: Optional[Dict[str, str]] = None

    # OAuth settings for HTTP
    oauth_client_id: Optional[str] = None
    oauth_client_secret: Optional[str] = None
    oauth_redirect_uri: Optional[str] = None

    @classmethod
    def from_dict(cls, name: str, config: Dict[str, Any]) -> "AWSQMCPServerConfig":
        """Create from AWS Q configuration dictionary"""
        transport_type = MCPTransportType.HTTP if config.get("type") == "http" else MCPTransportType.STDIO

        return cls(
            name=name,
            transport_type=transport_type,
            command=config.get("command"),
            args=config.get("args", []),
            env=config.get("env", {}),
            timeout=config.get("timeout", 30000),
            url=config.get("url"),
            headers=config.get("headers", {}),
            oauth_client_id=config.get("oauthClientId"),
            oauth_client_secret=config.get("oauthClientSecret"),
            oauth_redirect_uri=config.get("oauthRedirectUri")
        )


class AWSQConfigLoader:
    """Load and parse AWS Q MCP configuration files"""

    # AWS Q configuration locations
    GLOBAL_CLI_PATH = Path.home() / ".aws" / "amazonq" / "cli-agents"
    GLOBAL_IDE_PATH = Path.home() / ".aws" / "amazonq" / "agents"
    PROJECT_CLI_PATH = Path(".amazonq") / "cli-agents"
    PROJECT_IDE_PATH = Path(".amazonq") / "agents"

    @classmethod
    def find_config_files(cls, project_root: Optional[Path] = None) -> List[Path]:
        """Find all AWS Q MCP configuration files"""
        config_files = []

        # Check global locations
        for base_path in [cls.GLOBAL_CLI_PATH, cls.GLOBAL_IDE_PATH]:
            if base_path.exists():
                config_files.extend(base_path.glob("*.json"))

        # Check project-specific locations if provided
        if project_root:
            project_root = Path(project_root)
            for rel_path in [cls.PROJECT_CLI_PATH, cls.PROJECT_IDE_PATH]:
                project_path = project_root / rel_path
                if project_path.exists():
                    config_files.extend(project_path.glob("*.json"))

        # Also check for legacy mcp.json files
        legacy_paths = [
            Path.home() / ".aws" / "amazonq" / "mcp.json",
            Path(".amazonq") / "mcp.json"
        ]
        for path in legacy_paths:
            if path.exists():
                config_files.append(path)

        return config_files

    @classmethod
    def load_configuration(cls, config_file: Path) -> Dict[str, Any]:
        """Load an AWS Q agent configuration file"""
        try:
            with open(config_file, 'r') as f:
                config = json.load(f)

            # Validate required fields
            if not config.get("name"):
                logger.warning(f"Configuration {config_file} missing 'name' field")
                return None

            return config
        except Exception as e:
            logger.error(f"Failed to load configuration {config_file}: {e}")
            return None

    @classmethod
    def extract_mcp_servers(cls, config: Dict[str, Any]) -> Dict[str, AWSQMCPServerConfig]:
        """Extract MCP server configurations from AWS Q agent config"""
        mcp_servers = {}

        if "mcpServers" not in config:
            return mcp_servers

        for server_name, server_config in config["mcpServers"].items():
            try:
                mcp_server = AWSQMCPServerConfig.from_dict(server_name, server_config)
                mcp_servers[server_name] = mcp_server
            except Exception as e:
                logger.error(f"Failed to parse MCP server {server_name}: {e}")

        return mcp_servers


class STDIOBridge:
    """Bridge for STDIO-based MCP servers to HTTP endpoints"""

    def __init__(self, server_config: AWSQMCPServerConfig):
        self.config = server_config
        self.process = None
        self.bridge_port = None
        self.bridge_server = None

    async def start(self) -> str:
        """Start the STDIO process and create HTTP bridge

        Returns the HTTP endpoint URL for the bridge
        """
        try:
            # Prepare environment
            env = os.environ.copy()
            if self.config.env:
                env.update(self.config.env)

            # Start the MCP server process
            cmd = [self.config.command] + (self.config.args or [])
            self.process = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=env
            )

            # Find an available port for the bridge
            import socket
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.bind(('', 0))
                self.bridge_port = s.getsockname()[1]

            # Start HTTP-to-STDIO bridge server
            from aiohttp import web
            app = web.Application()
            app.router.add_post('/', self._handle_request)

            runner = web.AppRunner(app)
            await runner.setup()
            site = web.TCPSite(runner, 'localhost', self.bridge_port)
            await site.start()
            self.bridge_server = runner

            logger.info(f"Started STDIO bridge for {self.config.name} on port {self.bridge_port}")
            return f"http://localhost:{self.bridge_port}"

        except Exception as e:
            logger.error(f"Failed to start STDIO bridge for {self.config.name}: {e}")
            raise

    async def _handle_request(self, request):
        """Handle HTTP requests and forward to STDIO process"""
        from aiohttp import web

        try:
            # Read JSON-RPC request
            data = await request.json()

            # Send to process stdin
            self.process.stdin.write(json.dumps(data).encode() + b'\n')
            await self.process.stdin.drain()

            # Read response from stdout
            response_line = await asyncio.wait_for(
                self.process.stdout.readline(),
                timeout=self.config.timeout / 1000.0  # Convert to seconds
            )

            response = json.loads(response_line.decode())
            return web.json_response(response)

        except asyncio.TimeoutError:
            return web.json_response(
                {"error": {"code": -32000, "message": "Request timeout"}},
                status=504
            )
        except Exception as e:
            logger.error(f"Bridge request error: {e}")
            return web.json_response(
                {"error": {"code": -32603, "message": str(e)}},
                status=500
            )

    async def stop(self):
        """Stop the STDIO process and bridge"""
        if self.process:
            self.process.terminate()
            await self.process.wait()

        if self.bridge_server:
            await self.bridge_server.cleanup()


class AWSQMCPManager(MCPManager):
    """Extended MCP Manager with AWS Q configuration support"""

    def __init__(self):
        super().__init__()
        self.stdio_bridges: Dict[str, STDIOBridge] = {}
        self.awsq_configs: Dict[str, AWSQMCPServerConfig] = {}

    async def load_awsq_configurations(self, project_root: Optional[Path] = None) -> List[str]:
        """Load and initialize MCP servers from AWS Q configurations

        Returns list of loaded server names
        """
        loaded_servers = []

        # Find all configuration files
        config_files = AWSQConfigLoader.find_config_files(project_root)
        logger.info(f"Found {len(config_files)} AWS Q configuration files")

        for config_file in config_files:
            # Load the configuration
            config = AWSQConfigLoader.load_configuration(config_file)
            if not config:
                continue

            # Extract MCP servers
            mcp_servers = AWSQConfigLoader.extract_mcp_servers(config)

            for server_name, server_config in mcp_servers.items():
                try:
                    # Store the configuration
                    self.awsq_configs[server_name] = server_config

                    # Initialize based on transport type
                    if server_config.transport_type == MCPTransportType.HTTP:
                        # Direct HTTP connection
                        success = await self.add_server(
                            server_name,
                            server_config.url,
                            server_name
                        )
                        if success:
                            loaded_servers.append(server_name)

                    elif server_config.transport_type == MCPTransportType.STDIO:
                        # Create STDIO bridge
                        bridge = STDIOBridge(server_config)
                        endpoint = await bridge.start()
                        self.stdio_bridges[server_name] = bridge

                        # Connect via bridge endpoint
                        success = await self.add_server(
                            server_name,
                            endpoint,
                            server_name
                        )
                        if success:
                            loaded_servers.append(server_name)

                    logger.info(f"Loaded MCP server '{server_name}' from {config_file}")

                except Exception as e:
                    logger.error(f"Failed to load MCP server '{server_name}': {e}")

        return loaded_servers

    async def shutdown(self):
        """Shutdown all connections and bridges"""
        # Stop STDIO bridges
        for bridge in self.stdio_bridges.values():
            await bridge.stop()
        self.stdio_bridges.clear()

        # Call parent shutdown
        await super().shutdown()

    def get_server_config(self, server_name: str) -> Optional[AWSQMCPServerConfig]:
        """Get AWS Q configuration for a server"""
        return self.awsq_configs.get(server_name)

    def list_awsq_servers(self) -> Dict[str, Dict[str, Any]]:
        """List all AWS Q configured servers with their details"""
        servers = {}

        for name, config in self.awsq_configs.items():
            servers[name] = {
                "transport": config.transport_type.value,
                "command": config.command,
                "url": config.url,
                "connected": name in self.clients and self.clients[name].is_connected,
                "has_bridge": name in self.stdio_bridges
            }

        return servers


# Singleton instance
_awsq_manager = None


def get_awsq_mcp_manager() -> AWSQMCPManager:
    """Get or create AWS Q MCP manager instance"""
    global _awsq_manager
    if _awsq_manager is None:
        _awsq_manager = AWSQMCPManager()
    return _awsq_manager