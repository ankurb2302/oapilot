"""Storage management service for artifacts and database optimization"""

import os
import shutil
import sqlite3
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging

from app.core.config import settings
from app.core.database import engine, vacuum_database

logger = logging.getLogger(__name__)


class StorageManager:
    """Manage storage to stay within resource limits"""
    
    def __init__(self):
        self.storage_path = Path(settings.STORAGE_PATH)
        self.max_db_size = settings.MAX_DB_SIZE_MB * 1024 * 1024
        self.max_artifacts_size = settings.MAX_ARTIFACTS_SIZE_GB * 1024 * 1024 * 1024
        self.artifacts_path = self.storage_path / "artifacts"
        self.db_path = self.storage_path / "database" / "oapilot.db"
    
    def check_database_size(self) -> Dict:
        """Monitor database size"""
        if self.db_path.exists():
            size = self.db_path.stat().st_size
            return {
                "size_mb": round(size / (1024 * 1024), 2),
                "limit_mb": self.max_db_size / (1024 * 1024),
                "usage_percent": round((size / self.max_db_size) * 100, 2),
                "path": str(self.db_path)
            }
        return {
            "size_mb": 0,
            "limit_mb": self.max_db_size / (1024 * 1024),
            "usage_percent": 0,
            "path": str(self.db_path)
        }
    
    def check_artifacts_size(self) -> Dict:
        """Monitor artifacts storage"""
        total_size = 0
        file_count = 0
        
        if self.artifacts_path.exists():
            for f in self.artifacts_path.rglob("*"):
                if f.is_file():
                    total_size += f.stat().st_size
                    file_count += 1
        
        return {
            "size_gb": round(total_size / (1024**3), 2),
            "limit_gb": self.max_artifacts_size / (1024**3),
            "usage_percent": round((total_size / self.max_artifacts_size) * 100, 2),
            "file_count": file_count,
            "path": str(self.artifacts_path)
        }
    
    def get_storage_summary(self) -> Dict:
        """Get complete storage summary"""
        return {
            "database": self.check_database_size(),
            "artifacts": self.check_artifacts_size(),
            "total_usage_gb": round(
                (self.check_database_size()["size_mb"] / 1024) +
                self.check_artifacts_size()["size_gb"], 2
            )
        }
    
    async def cleanup_old_sessions(self, days: int = None):
        """Remove old sessions and their data"""
        days = days or settings.SESSION_RETENTION_DAYS
        cutoff_date = datetime.now() - timedelta(days=days)
        
        try:
            # Clean database
            conn = sqlite3.connect(str(self.db_path))
            cursor = conn.cursor()
            
            # Get sessions to delete
            cursor.execute("""
                SELECT session_id FROM chat_sessions 
                WHERE created_at < ?
            """, (cutoff_date.isoformat(),))
            
            old_sessions = [row[0] for row in cursor.fetchall()]
            
            if old_sessions:
                # Delete sessions (cascades to messages and artifacts)
                placeholders = ",".join("?" * len(old_sessions))
                cursor.execute(f"""
                    DELETE FROM chat_sessions 
                    WHERE session_id IN ({placeholders})
                """, old_sessions)
                
                deleted_count = cursor.rowcount
                conn.commit()
                
                # Clean up artifact files
                for session_id in old_sessions:
                    session_artifacts_path = self.artifacts_path / "*" / session_id
                    for path in self.storage_path.glob(str(session_artifacts_path)):
                        if path.is_dir():
                            shutil.rmtree(path)
                
                logger.info(f"Cleaned up {deleted_count} old sessions")
            
            conn.close()
            
            # Vacuum database to reclaim space
            await vacuum_database()
            
        except Exception as e:
            logger.error(f"Error cleaning up old sessions: {e}")
    
    async def cleanup_old_artifacts(self, days: int = None):
        """Remove old artifact files"""
        days = days or settings.ARTIFACT_RETENTION_DAYS
        cutoff_date = datetime.now() - timedelta(days=days)
        cutoff_timestamp = cutoff_date.timestamp()
        
        removed_count = 0
        removed_size = 0
        
        try:
            for artifact_type in ["code", "documents", "diagrams", "exports"]:
                type_path = self.artifacts_path / artifact_type
                if type_path.exists():
                    for file_path in type_path.rglob("*"):
                        if file_path.is_file():
                            if file_path.stat().st_mtime < cutoff_timestamp:
                                removed_size += file_path.stat().st_size
                                file_path.unlink()
                                removed_count += 1
            
            logger.info(f"Removed {removed_count} old artifacts ({removed_size / (1024*1024):.1f} MB)")
            
        except Exception as e:
            logger.error(f"Error cleaning up old artifacts: {e}")
    
    async def enforce_storage_limits(self):
        """Enforce storage limits by removing oldest data"""
        
        # Check database size
        db_info = self.check_database_size()
        if db_info["usage_percent"] > 80:
            logger.warning(f"Database usage at {db_info['usage_percent']}%, running cleanup")
            await self.cleanup_old_sessions(days=7)
        
        # Check artifacts size
        artifacts_info = self.check_artifacts_size()
        if artifacts_info["usage_percent"] > 80:
            logger.warning(f"Artifacts usage at {artifacts_info['usage_percent']}%, running cleanup")
            await self._cleanup_largest_artifacts()
    
    async def _cleanup_largest_artifacts(self):
        """Remove largest/oldest artifacts to free space"""
        target_usage = 60  # Target 60% usage
        target_size = self.max_artifacts_size * (target_usage / 100)
        
        # Get all artifact files with info
        files = []
        for f in self.artifacts_path.rglob("*"):
            if f.is_file():
                files.append({
                    "path": f,
                    "size": f.stat().st_size,
                    "mtime": f.stat().st_mtime
                })
        
        # Sort by size (largest first)
        files.sort(key=lambda x: x["size"], reverse=True)
        
        # Calculate current total size
        current_size = sum(f["size"] for f in files)
        
        # Remove files until under target
        removed_count = 0
        for file_info in files:
            if current_size <= target_size:
                break
            
            try:
                file_info["path"].unlink()
                current_size -= file_info["size"]
                removed_count += 1
            except Exception as e:
                logger.error(f"Failed to remove {file_info['path']}: {e}")
        
        logger.info(f"Removed {removed_count} large artifacts to free space")
    
    def get_artifact_path(
        self,
        artifact_type: str,
        session_id: str,
        filename: str
    ) -> Path:
        """Get the full path for an artifact"""
        return self.artifacts_path / artifact_type / session_id / filename
    
    def save_artifact_file(
        self,
        content: str,
        artifact_type: str,
        session_id: str,
        filename: str
    ) -> Dict:
        """Save an artifact file to storage"""
        file_path = self.get_artifact_path(artifact_type, session_id, filename)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            # Write content
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(content)
            
            # Get file info
            stat = file_path.stat()
            
            return {
                "path": str(file_path),
                "size_bytes": stat.st_size,
                "created": datetime.fromtimestamp(stat.st_mtime)
            }
            
        except Exception as e:
            logger.error(f"Failed to save artifact {filename}: {e}")
            raise
    
    def read_artifact_file(self, file_path: str) -> Optional[str]:
        """Read an artifact file"""
        path = Path(file_path)
        
        if not path.exists():
            return None
        
        try:
            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception as e:
            logger.error(f"Failed to read artifact {file_path}: {e}")
            return None
    
    def delete_artifact_file(self, file_path: str) -> bool:
        """Delete an artifact file"""
        path = Path(file_path)
        
        if not path.exists():
            return False
        
        try:
            path.unlink()
            return True
        except Exception as e:
            logger.error(f"Failed to delete artifact {file_path}: {e}")
            return False


# Global instance
storage_manager = None


def get_storage_manager() -> StorageManager:
    """Get or create storage manager instance"""
    global storage_manager
    if storage_manager is None:
        storage_manager = StorageManager()
    return storage_manager