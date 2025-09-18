"""Configuration management for OAPilot"""

from pydantic_settings import BaseSettings
from typing import Optional
import os
from pathlib import Path


class Settings(BaseSettings):
    """Application settings with resource optimization defaults"""
    
    # Server Configuration
    HOST: str = "0.0.0.0"
    PORT: int = 8080
    DEBUG: bool = False
    
    # Database
    DATABASE_URL: str = "sqlite:///./storage/database/oapilot.db"
    DB_CONNECTION_POOL_SIZE: int = 5
    DB_ENABLE_WAL: bool = True
    DB_CACHE_SIZE_KB: int = 64
    
    # Resource Management
    MAX_MEMORY_MB: int = 512
    MAX_DB_SIZE_MB: int = 1024
    MAX_ARTIFACTS_SIZE_GB: int = 5
    
    # LLM Settings (Memory-Optimized)
    LLM_MODEL: str = "phi3:mini"
    LLM_CONTEXT_SIZE: int = 2048
    LLM_MAX_TOKENS: int = 512
    LLM_NUM_THREADS: int = 4
    LLM_USE_MMAP: bool = True
    LLM_USE_MLOCK: bool = False
    LLM_BATCH_SIZE: int = 8
    OLLAMA_HOST: str = "http://localhost:11434"
    
    # MCP Connection Limits
    MAX_MCP_CONNECTIONS: int = 3
    MCP_TIMEOUT_SECONDS: int = 30
    MCP_RESPONSE_SIZE_LIMIT_MB: int = 10
    MCP_AUTO_DISCOVER: bool = True
    
    # Storage Management
    ARTIFACT_RETENTION_DAYS: int = 30
    SESSION_RETENTION_DAYS: int = 90
    AUTO_CLEANUP_ENABLED: bool = True
    STORAGE_PATH: str = "./storage"
    
    # API Limits
    MAX_REQUEST_SIZE_MB: int = 10
    PAGINATION_LIMIT: int = 20
    RATE_LIMIT_PER_MINUTE: int = 30
    
    # Security
    SECRET_KEY: str = "your-secret-key-here-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080  # 7 days
    
    # CORS
    CORS_ORIGINS: list = ["http://localhost:8080", "http://127.0.0.1:8080", "http://localhost:3000"]
    
    class Config:
        env_file = ".env"
        case_sensitive = True
    
    def get_storage_path(self, subpath: str = "") -> Path:
        """Get storage path with optional subpath"""
        base_path = Path(self.STORAGE_PATH)
        if subpath:
            return base_path / subpath
        return base_path
    
    def ensure_directories(self):
        """Ensure all required directories exist"""
        directories = [
            self.get_storage_path("database"),
            self.get_storage_path("artifacts/code"),
            self.get_storage_path("artifacts/documents"),
            self.get_storage_path("artifacts/diagrams"),
            self.get_storage_path("artifacts/exports"),
            self.get_storage_path("sessions"),
        ]
        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)


# Create global settings instance
settings = Settings()

# Ensure directories on import
settings.ensure_directories()