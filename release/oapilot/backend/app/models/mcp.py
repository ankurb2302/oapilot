"""MCP Server model"""

from sqlalchemy import Column, Integer, String, DateTime, JSON, Boolean
from datetime import datetime

from app.core.database import Base


class MCPServer(Base):
    """MCP Server configuration and status"""
    __tablename__ = "mcp_servers"
    
    id = Column(Integer, primary_key=True, index=True)
    server_id = Column(String(100), unique=True, index=True, nullable=False)
    name = Column(String(200), nullable=False)
    container_id = Column(String(100))
    endpoint = Column(String(500), nullable=False)
    status = Column(String(50), default="disconnected")  # "connected", "disconnected", "error"
    is_active = Column(Boolean, default=True)
    capabilities = Column(JSON)  # Available resources, tools, prompts
    last_health_check = Column(DateTime)
    error_message = Column(Text)
    metadata = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f"<MCPServer(server_id={self.server_id}, name={self.name}, status={self.status})>"