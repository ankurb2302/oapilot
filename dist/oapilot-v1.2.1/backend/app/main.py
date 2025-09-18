"""OAPilot FastAPI application"""

import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import logging
import sys
from pathlib import Path

# Add parent directory to Python path for module imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.config import settings
from app.core.database import init_db, engine
from app.core.llm_manager import get_llm_manager
from app.core.mcp_client import get_mcp_manager
from app.services.storage_manager import get_storage_manager
from app.api.v1 import chat, artifacts, mcp, system, awsq_mcp

# Configure logging
logging.basicConfig(
    level=logging.INFO if not settings.DEBUG else logging.DEBUG,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("oapilot.log")
    ]
)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager"""
    
    # Startup
    logger.info("Starting OAPilot...")
    
    # Initialize database
    init_db()
    logger.info("Database initialized")
    
    # Initialize LLM manager
    try:
        llm_manager = get_llm_manager()
        llm_manager.ensure_model()
        logger.info(f"LLM manager initialized with model: {settings.LLM_MODEL}")
    except Exception as e:
        logger.error(f"Failed to initialize LLM manager: {e}")
    
    # Initialize MCP manager (always use MCP config format, not Docker)
    try:
        from app.core.awsq_mcp_adapter import get_awsq_mcp_manager
        mcp_manager = get_awsq_mcp_manager()

        # Load MCP configurations from standard locations
        # OAPilot uses the same config format as AWS Q for compatibility
        loaded_servers = await mcp_manager.load_awsq_configurations(Path.cwd().parent)

        if loaded_servers:
            logger.info(f"MCP manager initialized with {len(loaded_servers)} servers from config files")
        else:
            logger.warning("No MCP server configurations found. Create config in .amazonq/cli-agents/")

    except Exception as e:
        logger.error(f"Failed to initialize MCP manager: {e}")
    
    # Initialize storage manager
    storage_manager = get_storage_manager()
    logger.info("Storage manager initialized")
    
    # Check and enforce storage limits on startup
    if settings.AUTO_CLEANUP_ENABLED:
        await storage_manager.enforce_storage_limits()
    
    yield
    
    # Shutdown
    logger.info("Shutting down OAPilot...")
    
    # Cleanup MCP connections
    if mcp_manager:
        await mcp_manager.shutdown()
    
    # Close database connections
    engine.dispose()
    
    logger.info("OAPilot shutdown complete")


# Create FastAPI app
app = FastAPI(
    title="OAPilot API",
    description="Offline AI Pilot System - Local LLM with MCP Integration",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "An internal error occurred"}
    )

# Include API routers
app.include_router(chat.router, prefix="/api/v1", tags=["chat"])
app.include_router(artifacts.router, prefix="/api/v1", tags=["artifacts"])
app.include_router(mcp.router, prefix="/api/v1", tags=["mcp"])
app.include_router(system.router, prefix="/api/v1", tags=["system"])
app.include_router(awsq_mcp.router, tags=["AWS Q MCP"])

# Health check endpoint
@app.get("/health")
async def health_check():
    """Basic health check endpoint"""
    return {
        "status": "healthy",
        "service": "oapilot",
        "version": "1.0.0"
    }

# Serve frontend static files (if built)
frontend_dist = Path("../frontend/dist")
if frontend_dist.exists():
    app.mount("/", StaticFiles(directory=str(frontend_dist), html=True), name="static")
    logger.info("Serving frontend from /frontend/dist")
else:
    @app.get("/")
    async def root():
        return {
            "message": "OAPilot API Server",
            "docs": "/docs",
            "health": "/health"
        }


if __name__ == "__main__":
    uvicorn.run(
        "app.main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
        log_level="info" if not settings.DEBUG else "debug",
        access_log=True
    )