"""Database configuration and session management"""

from sqlalchemy import create_engine, event
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from sqlalchemy.pool import StaticPool
from typing import Generator
import logging

from app.core.config import settings

logger = logging.getLogger(__name__)

# Create base class for models
Base = declarative_base()


def create_optimized_engine():
    """Create SQLite engine with optimizations for low memory usage"""
    
    # Create engine with single connection pool to minimize memory
    engine = create_engine(
        settings.DATABASE_URL,
        connect_args={
            "check_same_thread": False,
            "timeout": 15,
        },
        poolclass=StaticPool,  # Single connection, no pooling overhead
        echo=settings.DEBUG,
    )
    
    # Configure SQLite for efficiency
    @event.listens_for(engine, "connect")
    def set_sqlite_pragma(dbapi_conn, connection_record):
        cursor = dbapi_conn.cursor()
        
        # Enable Write-Ahead Logging for better concurrency and less memory
        if settings.DB_ENABLE_WAL:
            cursor.execute("PRAGMA journal_mode=WAL")
        
        # Set cache size (in KB)
        cache_pages = settings.DB_CACHE_SIZE_KB // 4  # SQLite page size is usually 4KB
        cursor.execute(f"PRAGMA cache_size={cache_pages}")
        
        # Use memory for temp tables
        cursor.execute("PRAGMA temp_store=MEMORY")
        
        # Synchronous mode - NORMAL is faster with slight risk
        cursor.execute("PRAGMA synchronous=NORMAL")
        
        # Enable foreign keys
        cursor.execute("PRAGMA foreign_keys=ON")
        
        # Optimize database periodically
        cursor.execute("PRAGMA optimize")
        
        cursor.close()
        
        logger.debug("SQLite pragmas set for optimized performance")
    
    return engine


# Create engine and session factory
engine = create_optimized_engine()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db() -> Generator[Session, None, None]:
    """Dependency to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Initialize database tables"""
    import app.models.chat  # Import models to register them
    import app.models.artifact
    import app.models.mcp
    
    Base.metadata.create_all(bind=engine)
    logger.info("Database initialized successfully")


def check_db_size() -> dict:
    """Check database file size"""
    import os
    from pathlib import Path
    
    db_path = Path(settings.DATABASE_URL.replace("sqlite:///", ""))
    if db_path.exists():
        size_bytes = os.path.getsize(db_path)
        size_mb = size_bytes / (1024 * 1024)
        max_size_mb = settings.MAX_DB_SIZE_MB
        
        return {
            "size_mb": round(size_mb, 2),
            "max_size_mb": max_size_mb,
            "usage_percent": round((size_mb / max_size_mb) * 100, 2)
        }
    
    return {"size_mb": 0, "max_size_mb": settings.MAX_DB_SIZE_MB, "usage_percent": 0}


async def vacuum_database():
    """Vacuum database to reclaim space"""
    with engine.connect() as conn:
        conn.execute("VACUUM")
        conn.commit()
    logger.info("Database vacuumed successfully")