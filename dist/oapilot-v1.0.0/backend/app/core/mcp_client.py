"""MCP Client implementation for connecting to MCP servers"""

import asyncio
import aiohttp
import json
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
import docker
from docker.errors import DockerException

from app.core.config import settings

logger = logging.getLogger(__name__)


class MCPClient:
    """Client for communicating with MCP servers via JSON-RPC"""
    
    def __init__(self, server_id: str, endpoint: str, name: str = ""):
        self.server_id = server_id
        self.endpoint = endpoint
        self.name = name or server_id
        self.session = None
        self.capabilities = {}
        self.is_connected = False
        self._request_id = 0
    
    async def connect(self) -> bool:
        """Establish connection to MCP server"""
        try:
            if not self.session:
                timeout = aiohttp.ClientTimeout(total=settings.MCP_TIMEOUT_SECONDS)
                self.session = aiohttp.ClientSession(timeout=timeout)
            
            # Initialize connection with MCP server
            response = await self._send_request("initialize", {
                "clientInfo": {
                    "name": "OAPilot",
                    "version": "1.0.0"
                }
            })
            
            if response and "result" in response:
                self.capabilities = response["result"].get("capabilities", {})
                self.is_connected = True
                logger.info(f"Connected to MCP server {self.name} at {self.endpoint}")
                return True
                
        except Exception as e:
            logger.error(f"Failed to connect to MCP server {self.name}: {e}")
            self.is_connected = False
            
        return False
    
    async def disconnect(self):
        """Disconnect from MCP server"""
        try:
            if self.session:
                await self.session.close()
                self.session = None
            self.is_connected = False
            logger.info(f"Disconnected from MCP server {self.name}")
        except Exception as e:
            logger.error(f"Error disconnecting from MCP server {self.name}: {e}")
    
    async def _send_request(self, method: str, params: Dict = None) -> Optional[Dict]:
        """Send JSON-RPC request to MCP server"""
        self._request_id += 1
        
        request = {
            "jsonrpc": "2.0",
            "id": self._request_id,
            "method": method
        }
        
        if params:
            request["params"] = params
        
        try:
            async with self.session.post(self.endpoint, json=request) as response:
                if response.status == 200:
                    return await response.json()
                else:
                    logger.error(f"MCP server {self.name} returned status {response.status}")
                    return None
                    
        except asyncio.TimeoutError:
            logger.error(f"Request to MCP server {self.name} timed out")
        except Exception as e:
            logger.error(f"Error sending request to MCP server {self.name}: {e}")
        
        return None
    
    async def list_resources(self) -> List[Dict]:
        """List available resources from MCP server"""
        if not self.is_connected:
            await self.connect()
        
        response = await self._send_request("resources/list")
        if response and "result" in response:
            return response["result"].get("resources", [])
        return []
    
    async def read_resource(self, resource_uri: str) -> Optional[Dict]:
        """Read a specific resource"""
        if not self.is_connected:
            await self.connect()
        
        response = await self._send_request("resources/read", {
            "uri": resource_uri
        })
        
        if response and "result" in response:
            return response["result"]
        return None
    
    async def list_tools(self) -> List[Dict]:
        """List available tools from MCP server"""
        if not self.is_connected:
            await self.connect()
        
        response = await self._send_request("tools/list")
        if response and "result" in response:
            return response["result"].get("tools", [])
        return []
    
    async def call_tool(self, tool_name: str, arguments: Dict = None) -> Optional[Dict]:
        """Call a tool on the MCP server"""
        if not self.is_connected:
            await self.connect()
        
        response = await self._send_request("tools/call", {
            "name": tool_name,
            "arguments": arguments or {}
        })
        
        if response and "result" in response:
            return response["result"]
        return None
    
    async def list_prompts(self) -> List[Dict]:
        """List available prompts from MCP server"""
        if not self.is_connected:
            await self.connect()
        
        response = await self._send_request("prompts/list")
        if response and "result" in response:
            return response["result"].get("prompts", [])
        return []
    
    async def get_prompt(self, prompt_name: str, arguments: Dict = None) -> Optional[str]:
        """Get a prompt template from the MCP server"""
        if not self.is_connected:
            await self.connect()
        
        response = await self._send_request("prompts/get", {
            "name": prompt_name,
            "arguments": arguments or {}
        })
        
        if response and "result" in response:
            messages = response["result"].get("messages", [])
            if messages:
                return messages[0].get("content", {}).get("text", "")
        return None
    
    async def health_check(self) -> bool:
        """Check if MCP server is healthy"""
        try:
            response = await self._send_request("ping")
            return response is not None
        except Exception:
            return False


class MCPDiscovery:
    """Discover and manage MCP servers running in Docker"""
    
    def __init__(self):
        self.docker_client = None
        self.mcp_servers = {}
    
    def _init_docker(self):
        """Initialize Docker client"""
        if not self.docker_client:
            try:
                self.docker_client = docker.from_env()
            except DockerException as e:
                logger.error(f"Failed to connect to Docker: {e}")
                raise
    
    async def discover_servers(self) -> List[Dict]:
        """Discover MCP servers running in Docker containers"""
        if not settings.MCP_AUTO_DISCOVER:
            return []
        
        self._init_docker()
        servers = []
        
        try:
            # Look for containers with MCP label or specific naming pattern
            containers = self.docker_client.containers.list(
                filters={"status": "running"}
            )
            
            for container in containers:
                # Check for MCP label or name pattern
                labels = container.labels
                name = container.name
                
                is_mcp = (
                    labels.get("mcp-server") == "true" or
                    "mcp" in name.lower() or
                    labels.get("com.modelcontextprotocol.server") == "true"
                )
                
                if is_mcp:
                    # Get container network info
                    networks = container.attrs["NetworkSettings"]["Networks"]
                    ports = container.attrs["NetworkSettings"]["Ports"]
                    
                    # Find the endpoint
                    endpoint = None
                    port = labels.get("mcp-port", "8000")
                    
                    # Try to get host port mapping
                    if ports:
                        for container_port, host_ports in ports.items():
                            if host_ports and container_port.startswith(str(port)):
                                endpoint = f"http://localhost:{host_ports[0]['HostPort']}"
                                break
                    
                    # Fallback to container IP
                    if not endpoint:
                        for network_info in networks.values():
                            if network_info.get("IPAddress"):
                                endpoint = f"http://{network_info['IPAddress']}:{port}"
                                break
                    
                    if endpoint:
                        server_info = {
                            "server_id": container.short_id,
                            "name": name,
                            "container_id": container.id,
                            "endpoint": endpoint,
                            "labels": labels,
                            "status": "discovered"
                        }
                        servers.append(server_info)
                        logger.info(f"Discovered MCP server: {name} at {endpoint}")
            
        except Exception as e:
            logger.error(f"Error discovering MCP servers: {e}")
        
        return servers
    
    def get_container_logs(self, container_id: str, lines: int = 100) -> str:
        """Get logs from a container"""
        self._init_docker()
        
        try:
            container = self.docker_client.containers.get(container_id)
            return container.logs(tail=lines).decode("utf-8")
        except Exception as e:
            logger.error(f"Failed to get container logs: {e}")
            return ""


class MCPManager:
    """Manage multiple MCP client connections"""
    
    def __init__(self):
        self.clients: Dict[str, MCPClient] = {}
        self.discovery = MCPDiscovery()
        self._lock = asyncio.Lock()
    
    async def initialize(self):
        """Initialize MCP manager and discover servers"""
        if settings.MCP_AUTO_DISCOVER:
            await self.auto_discover()
    
    async def auto_discover(self) -> List[Dict]:
        """Auto-discover and connect to MCP servers"""
        servers = await self.discovery.discover_servers()
        
        for server in servers:
            await self.add_server(
                server["server_id"],
                server["endpoint"],
                server["name"]
            )
        
        return servers
    
    async def add_server(self, server_id: str, endpoint: str, name: str = "") -> bool:
        """Add and connect to an MCP server"""
        async with self._lock:
            if server_id in self.clients:
                logger.warning(f"MCP server {server_id} already exists")
                return False
            
            # Check connection limit
            if len(self.clients) >= settings.MAX_MCP_CONNECTIONS:
                logger.warning(f"Maximum MCP connections ({settings.MAX_MCP_CONNECTIONS}) reached")
                return False
            
            client = MCPClient(server_id, endpoint, name)
            if await client.connect():
                self.clients[server_id] = client
                return True
            
            return False
    
    async def remove_server(self, server_id: str):
        """Remove and disconnect from an MCP server"""
        async with self._lock:
            if server_id in self.clients:
                await self.clients[server_id].disconnect()
                del self.clients[server_id]
    
    async def get_all_resources(self) -> Dict[str, List[Dict]]:
        """Get resources from all connected MCP servers"""
        resources = {}
        
        for server_id, client in self.clients.items():
            if client.is_connected:
                resources[server_id] = await client.list_resources()
        
        return resources
    
    async def execute_tool(self, server_id: str, tool_name: str, arguments: Dict) -> Dict:
        """Execute a tool on a specific MCP server"""
        if server_id not in self.clients:
            return {"success": False, "error": "Server not found"}
        
        client = self.clients[server_id]
        if not client.is_connected:
            await client.connect()
        
        try:
            result = await client.call_tool(tool_name, arguments)
            return {"success": True, "result": result}
        except Exception as e:
            return {"success": False, "error": str(e)}
    
    async def health_check_all(self) -> Dict[str, bool]:
        """Health check all MCP servers"""
        results = {}
        
        for server_id, client in self.clients.items():
            results[server_id] = await client.health_check()
        
        return results
    
    async def shutdown(self):
        """Shutdown all MCP connections"""
        for client in self.clients.values():
            await client.disconnect()
        self.clients.clear()


# Global instance
mcp_manager = None


def get_mcp_manager() -> MCPManager:
    """Get or create MCP manager instance"""
    global mcp_manager
    if mcp_manager is None:
        mcp_manager = MCPManager()
    return mcp_manager