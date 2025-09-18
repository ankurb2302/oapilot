"""System API endpoints for health, monitoring, and management"""

from fastapi import APIRouter, HTTPException
from datetime import datetime
import psutil
import logging

from app.core.config import settings
from app.core.llm_manager import get_llm_manager
from app.core.mcp_client import get_mcp_manager
from app.services.storage_manager import get_storage_manager
from app.models.schemas import HealthResponse, ResourceUsage

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def get_system_health():
    """Get comprehensive system health status"""
    
    services = {}
    
    # Check LLM service
    try:
        llm_manager = get_llm_manager()
        services["llm"] = "healthy" if llm_manager.current_model else "no_model"
    except Exception as e:
        services["llm"] = f"error: {str(e)}"
    
    # Check MCP service
    try:
        mcp_manager = get_mcp_manager()
        services["mcp"] = f"healthy ({len(mcp_manager.clients)} servers)"
    except Exception as e:
        services["mcp"] = f"error: {str(e)}"
    
    # Check storage
    try:
        storage_manager = get_storage_manager()
        storage_info = storage_manager.get_storage_summary()
        services["storage"] = "healthy"
    except Exception as e:
        services["storage"] = f"error: {str(e)}"
    
    # Get resource usage
    resources = await get_resource_usage()
    
    return HealthResponse(
        status="healthy" if all("error" not in s for s in services.values()) else "degraded",
        version="1.0.0",
        timestamp=datetime.now(),
        resources=resources.dict(),
        services=services
    )


@router.get("/resources", response_model=ResourceUsage)
async def get_resource_usage():
    """Get detailed resource usage information"""
    
    # Memory info
    mem = psutil.virtual_memory()
    memory = {
        "total_gb": round(mem.total / (1024**3), 2),
        "used_gb": round(mem.used / (1024**3), 2),
        "available_gb": round(mem.available / (1024**3), 2),
        "percent": round(mem.percent, 1)
    }
    
    # Disk info
    disk = psutil.disk_usage('/')
    disk_info = {
        "total_gb": round(disk.total / (1024**3), 2),
        "used_gb": round(disk.used / (1024**3), 2),
        "free_gb": round(disk.free / (1024**3), 2),
        "percent": round((disk.used / disk.total) * 100, 1)
    }
    
    # CPU info
    cpu = {
        "percent": round(psutil.cpu_percent(interval=1), 1),
        "cores": psutil.cpu_count(),
        "load_avg": psutil.getloadavg() if hasattr(psutil, 'getloadavg') else [0, 0, 0]
    }
    
    # Database info
    try:
        storage_manager = get_storage_manager()
        db_info = storage_manager.check_database_size()
        database = {
            "size_mb": db_info["size_mb"],
            "limit_mb": db_info["limit_mb"],
            "usage_percent": db_info["usage_percent"]
        }
    except Exception:
        database = {"size_mb": 0, "limit_mb": 0, "usage_percent": 0}
    
    # Artifacts info
    try:
        artifacts_info = storage_manager.check_artifacts_size()
        artifacts = {
            "size_gb": artifacts_info["size_gb"],
            "limit_gb": artifacts_info["limit_gb"],
            "usage_percent": artifacts_info["usage_percent"],
            "file_count": artifacts_info["file_count"]
        }
    except Exception:
        artifacts = {"size_gb": 0, "limit_gb": 0, "usage_percent": 0, "file_count": 0}
    
    return ResourceUsage(
        memory=memory,
        disk=disk_info,
        cpu=cpu,
        database=database,
        artifacts=artifacts
    )


@router.get("/models")
async def list_available_models():
    """List available LLM models"""
    
    try:
        llm_manager = get_llm_manager()
        models = llm_manager.list_available_models()
        
        # Add recommended models info
        lightweight_models = []
        for model_name, info in llm_manager.LIGHTWEIGHT_MODELS.items():
            is_available = any(m["name"] == model_name for m in models)
            lightweight_models.append({
                **info,
                "name": model_name,
                "available": is_available,
                "current": model_name == llm_manager.current_model
            })
        
        return {
            "current_model": llm_manager.current_model,
            "available_models": models,
            "recommended_models": lightweight_models
        }
    except Exception as e:
        logger.error(f"Failed to list models: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to list models: {str(e)}")


@router.post("/models/switch")
async def switch_model(model_name: str):
    """Switch to a different LLM model"""
    
    try:
        llm_manager = get_llm_manager()
        
        # Check memory before switching
        mem = psutil.virtual_memory()
        available_gb = mem.available / (1024**3)
        
        model_info = llm_manager.LIGHTWEIGHT_MODELS.get(model_name, {})
        required_gb = model_info.get("size_gb", 4.0)
        
        if available_gb < required_gb + 1:
            raise HTTPException(
                status_code=400,
                detail=f"Insufficient memory. Need {required_gb+1:.1f}GB, have {available_gb:.1f}GB"
            )
        
        # Ensure model is available
        success = llm_manager.ensure_model(model_name)
        
        if success:
            return {
                "status": "success",
                "previous_model": llm_manager.current_model,
                "current_model": model_name,
                "model_info": model_info
            }
        else:
            raise HTTPException(status_code=400, detail="Failed to switch model")
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to switch model: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to switch model: {str(e)}")


@router.post("/models/pull")
async def pull_model(model_name: str):
    """Pull a new model"""
    
    try:
        llm_manager = get_llm_manager()
        
        # Check if model is in recommended list
        if model_name not in llm_manager.LIGHTWEIGHT_MODELS:
            logger.warning(f"Model {model_name} not in recommended list")
        
        success = llm_manager.ensure_model(model_name)
        
        if success:
            return {
                "status": "success",
                "model": model_name,
                "message": f"Model {model_name} pulled successfully"
            }
        else:
            raise HTTPException(status_code=400, detail="Failed to pull model")
            
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to pull model: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to pull model: {str(e)}")


@router.post("/storage/cleanup")
async def trigger_storage_cleanup():
    """Trigger storage cleanup"""
    
    try:
        storage_manager = get_storage_manager()
        
        # Get before stats
        before_stats = storage_manager.get_storage_summary()
        
        # Run cleanup
        await storage_manager.enforce_storage_limits()
        await storage_manager.cleanup_old_sessions(days=7)
        await storage_manager.cleanup_old_artifacts(days=7)
        
        # Get after stats
        after_stats = storage_manager.get_storage_summary()
        
        return {
            "status": "success",
            "before": before_stats,
            "after": after_stats,
            "freed_gb": round(
                before_stats["total_usage_gb"] - after_stats["total_usage_gb"], 2
            )
        }
        
    except Exception as e:
        logger.error(f"Storage cleanup failed: {e}")
        raise HTTPException(status_code=500, detail=f"Cleanup failed: {str(e)}")


@router.get("/storage")
async def get_storage_info():
    """Get detailed storage information"""
    
    try:
        storage_manager = get_storage_manager()
        return storage_manager.get_storage_summary()
    except Exception as e:
        logger.error(f"Failed to get storage info: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get storage info: {str(e)}")


@router.get("/config")
async def get_configuration():
    """Get current system configuration"""
    
    return {
        "llm": {
            "model": settings.LLM_MODEL,
            "context_size": settings.LLM_CONTEXT_SIZE,
            "max_tokens": settings.LLM_MAX_TOKENS,
            "ollama_host": settings.OLLAMA_HOST
        },
        "mcp": {
            "max_connections": settings.MAX_MCP_CONNECTIONS,
            "timeout_seconds": settings.MCP_TIMEOUT_SECONDS,
            "auto_discover": settings.MCP_AUTO_DISCOVER
        },
        "storage": {
            "max_db_size_mb": settings.MAX_DB_SIZE_MB,
            "max_artifacts_size_gb": settings.MAX_ARTIFACTS_SIZE_GB,
            "retention_days": settings.SESSION_RETENTION_DAYS,
            "auto_cleanup": settings.AUTO_CLEANUP_ENABLED
        },
        "api": {
            "host": settings.HOST,
            "port": settings.PORT,
            "pagination_limit": settings.PAGINATION_LIMIT,
            "max_request_size_mb": settings.MAX_REQUEST_SIZE_MB
        }
    }


@router.get("/logs")
async def get_recent_logs(lines: int = 100):
    """Get recent application logs"""
    
    try:
        import os
        log_file = "oapilot.log"
        
        if not os.path.exists(log_file):
            return {"logs": [], "message": "No log file found"}
        
        with open(log_file, "r") as f:
            all_lines = f.readlines()
            recent_lines = all_lines[-lines:] if len(all_lines) > lines else all_lines
        
        return {
            "logs": [line.strip() for line in recent_lines],
            "total_lines": len(all_lines),
            "returned_lines": len(recent_lines)
        }
        
    except Exception as e:
        logger.error(f"Failed to get logs: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to get logs: {str(e)}")


@router.post("/restart")
async def restart_services():
    """Restart core services"""
    
    try:
        # Restart MCP manager
        mcp_manager = get_mcp_manager()
        await mcp_manager.shutdown()
        await mcp_manager.initialize()
        
        # Reload LLM manager
        llm_manager = get_llm_manager()
        llm_manager.ensure_model()
        
        return {
            "status": "success",
            "message": "Services restarted successfully",
            "timestamp": datetime.now()
        }
        
    except Exception as e:
        logger.error(f"Failed to restart services: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to restart services: {str(e)}")