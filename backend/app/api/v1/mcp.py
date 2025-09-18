"""MCP Server API endpoints"""

from fastapi import APIRouter, HTTPException
from typing import List, Dict, Any
import logging

from app.core.mcp_client import get_mcp_manager
from app.models.schemas import MCPServerInfo, MCPExecuteRequest, MCPExecuteResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/mcp/servers", response_model=List[MCPServerInfo])
async def list_mcp_servers():
    """List all registered MCP servers"""
    
    mcp_manager = get_mcp_manager()
    
    servers = []
    for server_id, client in mcp_manager.clients.items():
        servers.append(MCPServerInfo(
            server_id=server_id,
            name=client.name,
            container_id=getattr(client, 'container_id', None),
            endpoint=client.endpoint,
            status="connected" if client.is_connected else "disconnected",
            is_active=client.is_connected,
            capabilities=client.capabilities,
            last_health_check=None,  # TODO: Implement health check tracking
            error_message=None
        ))
    
    return servers


@router.post("/mcp/discover")
async def discover_mcp_servers():
    """Trigger MCP server discovery"""
    
    mcp_manager = get_mcp_manager()
    
    try:
        discovered = await mcp_manager.auto_discover()
        return {
            "status": "success",
            "discovered_count": len(discovered),
            "servers": discovered
        }
    except Exception as e:
        logger.error(f"MCP discovery failed: {e}")
        raise HTTPException(status_code=500, detail=f"Discovery failed: {str(e)}")


@router.get("/mcp/servers/{server_id}/resources")
async def list_server_resources(server_id: str):
    """List resources from a specific MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    client = mcp_manager.clients[server_id]
    
    try:
        resources = await client.list_resources()
        return {
            "server_id": server_id,
            "resources": resources
        }
    except Exception as e:
        logger.error(f"Failed to list resources from {server_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get resources: {str(e)}")


@router.get("/mcp/servers/{server_id}/tools")
async def list_server_tools(server_id: str):
    """List tools from a specific MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    client = mcp_manager.clients[server_id]
    
    try:
        tools = await client.list_tools()
        return {
            "server_id": server_id,
            "tools": tools
        }
    except Exception as e:
        logger.error(f"Failed to list tools from {server_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get tools: {str(e)}")


@router.get("/mcp/servers/{server_id}/prompts")
async def list_server_prompts(server_id: str):
    """List prompts from a specific MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    client = mcp_manager.clients[server_id]
    
    try:
        prompts = await client.list_prompts()
        return {
            "server_id": server_id,
            "prompts": prompts
        }
    except Exception as e:
        logger.error(f"Failed to list prompts from {server_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get prompts: {str(e)}")


@router.post("/mcp/execute", response_model=MCPExecuteResponse)
async def execute_mcp_tool(request: MCPExecuteRequest):
    """Execute a tool on an MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    try:
        result = await mcp_manager.execute_tool(
            request.server_id,
            request.tool_name,
            request.parameters
        )
        
        return MCPExecuteResponse(
            success=result["success"],
            result=result.get("result"),
            error=result.get("error"),
            execution_time=0.0  # TODO: Implement timing
        )
        
    except Exception as e:
        logger.error(f"Failed to execute tool: {e}")
        return MCPExecuteResponse(
            success=False,
            error=str(e),
            execution_time=0.0
        )


@router.get("/mcp/servers/{server_id}/resources/{resource_uri}")
async def read_mcp_resource(server_id: str, resource_uri: str):
    """Read a specific resource from an MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    client = mcp_manager.clients[server_id]
    
    try:
        # Decode URI if needed
        import urllib.parse
        decoded_uri = urllib.parse.unquote(resource_uri)
        
        resource = await client.read_resource(decoded_uri)
        
        if resource is None:
            raise HTTPException(status_code=404, detail="Resource not found")
        
        return {
            "server_id": server_id,
            "resource_uri": decoded_uri,
            "resource": resource
        }
        
    except Exception as e:
        logger.error(f"Failed to read resource {resource_uri} from {server_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to read resource: {str(e)}")


@router.get("/mcp/servers/{server_id}/prompts/{prompt_name}")
async def get_mcp_prompt(
    server_id: str, 
    prompt_name: str,
    arguments: Dict[str, Any] = None
):
    """Get a prompt template from an MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    client = mcp_manager.clients[server_id]
    
    try:
        prompt = await client.get_prompt(prompt_name, arguments or {})
        
        if prompt is None:
            raise HTTPException(status_code=404, detail="Prompt not found")
        
        return {
            "server_id": server_id,
            "prompt_name": prompt_name,
            "prompt": prompt,
            "arguments": arguments
        }
        
    except Exception as e:
        logger.error(f"Failed to get prompt {prompt_name} from {server_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get prompt: {str(e)}")


@router.post("/mcp/servers/{server_id}/health")
async def check_server_health(server_id: str):
    """Check health of a specific MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    client = mcp_manager.clients[server_id]
    
    try:
        is_healthy = await client.health_check()
        return {
            "server_id": server_id,
            "healthy": is_healthy,
            "status": "connected" if is_healthy else "disconnected"
        }
    except Exception as e:
        logger.error(f"Health check failed for {server_id}: {e}")
        return {
            "server_id": server_id,
            "healthy": False,
            "status": "error",
            "error": str(e)
        }


@router.get("/mcp/health")
async def check_all_servers_health():
    """Check health of all MCP servers"""
    
    mcp_manager = get_mcp_manager()
    
    try:
        health_results = await mcp_manager.health_check_all()
        
        return {
            "total_servers": len(mcp_manager.clients),
            "healthy_servers": sum(1 for healthy in health_results.values() if healthy),
            "results": {
                server_id: {
                    "healthy": is_healthy,
                    "status": "connected" if is_healthy else "disconnected"
                }
                for server_id, is_healthy in health_results.items()
            }
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        raise HTTPException(status_code=500, detail=f"Health check failed: {str(e)}")


@router.post("/mcp/servers/add")
async def add_mcp_server(
    server_id: str,
    endpoint: str,
    name: str = ""
):
    """Manually add an MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    try:
        success = await mcp_manager.add_server(server_id, endpoint, name)
        
        if success:
            return {
                "status": "success",
                "server_id": server_id,
                "endpoint": endpoint,
                "name": name
            }
        else:
            raise HTTPException(status_code=400, detail="Failed to add server")
            
    except Exception as e:
        logger.error(f"Failed to add MCP server: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to add server: {str(e)}")


@router.delete("/mcp/servers/{server_id}")
async def remove_mcp_server(server_id: str):
    """Remove an MCP server"""
    
    mcp_manager = get_mcp_manager()
    
    if server_id not in mcp_manager.clients:
        raise HTTPException(status_code=404, detail="MCP server not found")
    
    try:
        await mcp_manager.remove_server(server_id)
        return {
            "status": "removed",
            "server_id": server_id
        }
    except Exception as e:
        logger.error(f"Failed to remove MCP server: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to remove server: {str(e)}")


@router.get("/mcp/resources/all")
async def get_all_resources():
    """Get all resources from all connected MCP servers"""
    
    mcp_manager = get_mcp_manager()
    
    try:
        all_resources = await mcp_manager.get_all_resources()
        
        return {
            "total_servers": len(all_resources),
            "resources": all_resources
        }
    except Exception as e:
        logger.error(f"Failed to get all resources: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get resources: {str(e)}")