"""Pydantic schemas for API requests and responses"""

from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum


class MessageRole(str, Enum):
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"


class ArtifactType(str, Enum):
    CODE = "code"
    DOCUMENT = "document"
    DIAGRAM = "diagram"
    DATA = "data"


# Chat Schemas
class ChatSessionCreate(BaseModel):
    title: Optional[str] = Field(None, max_length=200)
    model: Optional[str] = Field("phi3:mini", max_length=100)


class ChatSessionResponse(BaseModel):
    session_id: str
    title: Optional[str]
    created_at: datetime
    updated_at: datetime
    model_used: Optional[str]
    message_count: int = 0
    total_tokens: int = 0
    
    class Config:
        from_attributes = True


class ChatMessageCreate(BaseModel):
    content: str = Field(..., min_length=1, max_length=10000)
    use_mcp: bool = Field(True, description="Use MCP servers for context")
    mcp_servers: Optional[List[str]] = Field(None, description="Specific MCP servers to use")


class ChatMessageResponse(BaseModel):
    message_id: str
    session_id: str
    role: MessageRole
    content: str
    mcp_resources_used: Optional[Dict[str, Any]]
    timestamp: datetime
    tokens_used: Optional[Dict[str, int]]
    processing_time: Optional[float]
    
    class Config:
        from_attributes = True


class QueryRequest(BaseModel):
    query: str = Field(..., min_length=1, max_length=10000)
    session_id: Optional[str] = None
    context: Optional[Dict[str, Any]] = None
    use_mcp: bool = True
    model: Optional[str] = Field("phi3:mini", max_length=100)


class QueryResponse(BaseModel):
    query_id: str
    status: str  # "processing", "completed", "error"
    created_at: datetime


class QueryResult(BaseModel):
    query_id: str
    response: str
    mcp_resources_used: Optional[List[Dict[str, Any]]]
    processing_time: float
    model_used: str
    tokens_used: Dict[str, int]
    artifacts: Optional[List['ArtifactResponse']]


# Artifact Schemas
class ArtifactCreate(BaseModel):
    type: ArtifactType
    name: str = Field(..., min_length=1, max_length=200)
    content: str
    description: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class ArtifactResponse(BaseModel):
    artifact_id: str
    session_id: str
    message_id: Optional[str]
    type: str
    name: str
    description: Optional[str]
    file_path: Optional[str]
    mime_type: Optional[str]
    size_bytes: Optional[int]
    metadata: Optional[Dict[str, Any]]
    created_at: datetime
    
    class Config:
        from_attributes = True


# MCP Schemas
class MCPServerInfo(BaseModel):
    server_id: str
    name: str
    container_id: Optional[str]
    endpoint: str
    status: str
    is_active: bool
    capabilities: Optional[Dict[str, Any]]
    last_health_check: Optional[datetime]
    error_message: Optional[str]
    
    class Config:
        from_attributes = True


class MCPExecuteRequest(BaseModel):
    server_id: str
    tool_name: str
    parameters: Dict[str, Any]


class MCPExecuteResponse(BaseModel):
    success: bool
    result: Optional[Any]
    error: Optional[str]
    execution_time: float


# System Schemas
class HealthResponse(BaseModel):
    status: str
    version: str
    timestamp: datetime
    resources: Dict[str, Any]
    services: Dict[str, str]


class ResourceUsage(BaseModel):
    memory: Dict[str, float]
    disk: Dict[str, float]
    cpu: Dict[str, float]
    database: Dict[str, float]
    artifacts: Dict[str, float]


# Update forward references
QueryResult.model_rebuild()