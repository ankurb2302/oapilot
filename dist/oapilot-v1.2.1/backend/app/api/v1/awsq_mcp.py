"""AWS Q MCP API endpoints for managing MCP servers via AWS Q configuration"""

from fastapi import APIRouter, HTTPException, Depends
from typing import Dict, List, Any
from pathlib import Path
import logging

from app.core.awsq_mcp_adapter import get_awsq_mcp_manager, AWSQConfigLoader
from app.models.schemas import MCPServerResponse, MCPResourceResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v1/awsq-mcp", tags=["AWS Q MCP"])


@router.get("/configurations")
async def list_configurations() -> Dict[str, Any]:
    """List all available AWS Q MCP configurations"""
    try:
        # Find configuration files
        global_configs = AWSQConfigLoader.find_config_files()
        project_configs = AWSQConfigLoader.find_config_files(Path.cwd())

        configurations = []

        # Load and parse configurations
        for config_file in set(global_configs + project_configs):
            config = AWSQConfigLoader.load_configuration(config_file)
            if config:
                mcp_servers = AWSQConfigLoader.extract_mcp_servers(config)
                configurations.append({
                    "file": str(config_file),
                    "name": config.get("name"),
                    "description": config.get("description"),
                    "servers": list(mcp_servers.keys()),
                    "scope": "global" if ".aws" in str(config_file) else "project"
                })

        return {
            "success": True,
            "configurations": configurations,
            "count": len(configurations)
        }

    except Exception as e:
        logger.error(f"Failed to list AWS Q configurations: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/load")
async def load_awsq_servers(project_root: str = None) -> Dict[str, Any]:
    """Load MCP servers from AWS Q configuration files"""
    try:
        manager = get_awsq_mcp_manager()

        # Load configurations
        project_path = Path(project_root) if project_root else None
        loaded_servers = await manager.load_awsq_configurations(project_path)

        return {
            "success": True,
            "message": f"Loaded {len(loaded_servers)} MCP servers from AWS Q configurations",
            "servers": loaded_servers
        }

    except Exception as e:
        logger.error(f"Failed to load AWS Q MCP servers: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/servers")
async def list_awsq_servers() -> Dict[str, Any]:
    """List all AWS Q configured MCP servers and their status"""
    try:
        manager = get_awsq_mcp_manager()
        servers = manager.list_awsq_servers()

        return {
            "success": True,
            "servers": servers,
            "count": len(servers)
        }

    except Exception as e:
        logger.error(f"Failed to list AWS Q MCP servers: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/servers/{server_name}/config")
async def get_server_config(server_name: str) -> Dict[str, Any]:
    """Get configuration details for a specific AWS Q MCP server"""
    try:
        manager = get_awsq_mcp_manager()
        config = manager.get_server_config(server_name)

        if not config:
            raise HTTPException(status_code=404, detail=f"Server '{server_name}' not found")

        return {
            "success": True,
            "server": server_name,
            "config": {
                "transport": config.transport_type.value,
                "command": config.command,
                "args": config.args,
                "env": config.env,
                "url": config.url,
                "timeout": config.timeout
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get server config: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/servers/{server_name}/restart")
async def restart_server(server_name: str) -> Dict[str, Any]:
    """Restart an AWS Q MCP server (STDIO bridges only)"""
    try:
        manager = get_awsq_mcp_manager()

        # Check if it's a STDIO bridge
        if server_name not in manager.stdio_bridges:
            return {
                "success": False,
                "message": f"Server '{server_name}' is not a STDIO bridge or not loaded"
            }

        # Stop the bridge
        bridge = manager.stdio_bridges[server_name]
        await bridge.stop()

        # Remove from manager
        await manager.remove_server(server_name)
        del manager.stdio_bridges[server_name]

        # Restart the bridge
        config = manager.get_server_config(server_name)
        if config:
            from app.core.awsq_mcp_adapter import STDIOBridge
            new_bridge = STDIOBridge(config)
            endpoint = await new_bridge.start()
            manager.stdio_bridges[server_name] = new_bridge

            # Reconnect
            success = await manager.add_server(server_name, endpoint, server_name)

            return {
                "success": success,
                "message": f"Server '{server_name}' restarted successfully" if success else "Failed to reconnect"
            }

        return {
            "success": False,
            "message": "Server configuration not found"
        }

    except Exception as e:
        logger.error(f"Failed to restart server: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/migrate-from-docker")
async def migrate_from_docker() -> Dict[str, Any]:
    """
    Analyze current Docker-based MCP servers and suggest AWS Q configuration.
    This helps users migrate from docker-compose to AWS Q MCP configuration.
    """
    try:
        from app.core.mcp_client import MCPDiscovery
        import json

        discovery = MCPDiscovery()
        docker_servers = await discovery.discover_servers()

        # Generate AWS Q configuration suggestions
        suggested_config = {
            "name": "migrated-from-docker",
            "description": "MCP servers migrated from Docker configuration",
            "mcpServers": {}
        }

        migration_notes = []

        for server in docker_servers:
            server_name = server["name"]
            labels = server.get("labels", {})

            # Determine if it can be run as STDIO or needs HTTP
            if labels.get("mcp-command"):
                # Can be converted to STDIO
                suggested_config["mcpServers"][server_name] = {
                    "command": labels["mcp-command"],
                    "args": json.loads(labels.get("mcp-args", "[]")),
                    "env": json.loads(labels.get("mcp-env", "{}")),
                    "timeout": 30000
                }
                migration_notes.append(f"✓ {server_name}: Can be migrated to STDIO transport")
            else:
                # Keep as HTTP
                suggested_config["mcpServers"][server_name] = {
                    "type": "http",
                    "url": server["endpoint"]
                }
                migration_notes.append(f"⚠ {server_name}: Will use HTTP transport (requires running container)")

        # Save suggested configuration
        output_path = Path(".amazonq/cli-agents/migrated.json")
        output_path.parent.mkdir(parents=True, exist_ok=True)

        with open(output_path, 'w') as f:
            json.dump(suggested_config, f, indent=2)

        return {
            "success": True,
            "message": "Migration analysis complete",
            "docker_servers_found": len(docker_servers),
            "suggested_config_saved": str(output_path),
            "migration_notes": migration_notes,
            "next_steps": [
                "1. Review the generated configuration in .amazonq/cli-agents/migrated.json",
                "2. Install MCP server binaries for STDIO servers",
                "3. Update environment variables and paths as needed",
                "4. Test with: q mcp load workspace",
                "5. Remove docker-compose.yml once migration is verified"
            ]
        }

    except Exception as e:
        logger.error(f"Migration analysis failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/health-check")
async def health_check_all() -> Dict[str, Any]:
    """Health check all AWS Q configured MCP servers"""
    try:
        manager = get_awsq_mcp_manager()
        results = await manager.health_check_all()

        return {
            "success": True,
            "servers": results,
            "healthy": sum(1 for v in results.values() if v),
            "total": len(results)
        }

    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))