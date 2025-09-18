#!/usr/bin/env python3
"""
Backend startup script that handles Python path correctly
"""
import sys
from pathlib import Path

# Add backend directory to Python path
backend_dir = Path(__file__).parent
sys.path.insert(0, str(backend_dir))

# Initialize database and start the application
if __name__ == "__main__":
    # Initialize database first
    try:
        from app.core.database import init_db
        init_db()
        print("Database initialized successfully")
    except Exception as e:
        print(f"Database initialization failed: {e}")
        sys.exit(1)

    # Start the FastAPI application
    try:
        from app.main import app
        import uvicorn

        # Get configuration
        from app.core.config import settings

        uvicorn.run(
            app,
            host=settings.HOST,
            port=settings.PORT,
            reload=settings.DEBUG,
            log_level="info" if not settings.DEBUG else "debug",
            access_log=True
        )
    except Exception as e:
        print(f"Failed to start backend: {e}")
        sys.exit(1)