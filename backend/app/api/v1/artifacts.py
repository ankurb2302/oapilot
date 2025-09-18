"""Artifacts API endpoints"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import uuid4
import logging

from app.core.database import get_db
from app.services.storage_manager import get_storage_manager
from app.models.artifact import Artifact
from app.models.schemas import ArtifactCreate, ArtifactResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/artifacts", response_model=ArtifactResponse)
async def create_artifact(
    artifact_create: ArtifactCreate,
    session_id: str,
    message_id: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Create a new artifact"""
    
    artifact_id = str(uuid4())
    storage_manager = get_storage_manager()
    
    # Determine file extension
    extensions = {
        "code": ".py",
        "javascript": ".js",
        "typescript": ".ts",
        "document": ".md",
        "diagram": ".svg",
        "data": ".json"
    }
    
    ext = extensions.get(artifact_create.type.value, ".txt")
    filename = f"{artifact_create.name.replace(' ', '_')}{ext}"
    
    try:
        # Save file to storage
        file_info = storage_manager.save_artifact_file(
            content=artifact_create.content,
            artifact_type=artifact_create.type.value,
            session_id=session_id,
            filename=filename
        )
        
        # Create database record
        artifact = Artifact(
            artifact_id=artifact_id,
            session_id=session_id,
            message_id=message_id,
            type=artifact_create.type.value,
            name=artifact_create.name,
            description=artifact_create.description,
            file_path=file_info["path"],
            mime_type=_get_mime_type(artifact_create.type.value),
            size_bytes=file_info["size_bytes"],
            custom_metadata=artifact_create.custom_metadata or {}
        )
        
        db.add(artifact)
        db.commit()
        db.refresh(artifact)
        
        return ArtifactResponse(
            artifact_id=artifact.artifact_id,
            session_id=artifact.session_id,
            message_id=artifact.message_id,
            type=artifact.type,
            name=artifact.name,
            description=artifact.description,
            file_path=artifact.file_path,
            mime_type=artifact.mime_type,
            size_bytes=artifact.size_bytes,
            custom_metadata=artifact.custom_metadata,
            created_at=artifact.created_at
        )
        
    except Exception as e:
        logger.error(f"Failed to create artifact: {e}")
        raise HTTPException(status_code=500, detail="Failed to create artifact")


@router.get("/artifacts", response_model=List[ArtifactResponse])
async def list_artifacts(
    session_id: Optional[str] = None,
    artifact_type: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    db: Session = Depends(get_db)
):
    """List artifacts with optional filtering"""
    
    query = db.query(Artifact)
    
    if session_id:
        query = query.filter(Artifact.session_id == session_id)
    
    if artifact_type:
        query = query.filter(Artifact.type == artifact_type)
    
    artifacts = query.order_by(Artifact.created_at.desc()).offset(skip).limit(limit).all()
    
    return [
        ArtifactResponse(
            artifact_id=artifact.artifact_id,
            session_id=artifact.session_id,
            message_id=artifact.message_id,
            type=artifact.type,
            name=artifact.name,
            description=artifact.description,
            file_path=artifact.file_path,
            mime_type=artifact.mime_type,
            size_bytes=artifact.size_bytes,
            custom_metadata=artifact.custom_metadata,
            created_at=artifact.created_at
        )
        for artifact in artifacts
    ]


@router.get("/artifacts/{artifact_id}", response_model=ArtifactResponse)
async def get_artifact(
    artifact_id: str,
    db: Session = Depends(get_db)
):
    """Get a specific artifact"""
    
    artifact = db.query(Artifact).filter(
        Artifact.artifact_id == artifact_id
    ).first()
    
    if not artifact:
        raise HTTPException(status_code=404, detail="Artifact not found")
    
    return ArtifactResponse(
        artifact_id=artifact.artifact_id,
        session_id=artifact.session_id,
        message_id=artifact.message_id,
        type=artifact.type,
        name=artifact.name,
        description=artifact.description,
        file_path=artifact.file_path,
        mime_type=artifact.mime_type,
        size_bytes=artifact.size_bytes,
        custom_metadata=artifact.custom_metadata,
        created_at=artifact.created_at
    )


@router.get("/artifacts/{artifact_id}/content")
async def get_artifact_content(
    artifact_id: str,
    db: Session = Depends(get_db)
):
    """Get the content of an artifact"""
    
    artifact = db.query(Artifact).filter(
        Artifact.artifact_id == artifact_id
    ).first()
    
    if not artifact:
        raise HTTPException(status_code=404, detail="Artifact not found")
    
    storage_manager = get_storage_manager()
    content = storage_manager.read_artifact_file(artifact.file_path)
    
    if content is None:
        raise HTTPException(status_code=404, detail="Artifact file not found")
    
    return {
        "artifact_id": artifact_id,
        "name": artifact.name,
        "type": artifact.type,
        "content": content,
        "mime_type": artifact.mime_type
    }


@router.get("/artifacts/{artifact_id}/download")
async def download_artifact(
    artifact_id: str,
    db: Session = Depends(get_db)
):
    """Download an artifact file"""
    
    artifact = db.query(Artifact).filter(
        Artifact.artifact_id == artifact_id
    ).first()
    
    if not artifact:
        raise HTTPException(status_code=404, detail="Artifact not found")
    
    import os
    if not os.path.exists(artifact.file_path):
        raise HTTPException(status_code=404, detail="Artifact file not found")
    
    return FileResponse(
        path=artifact.file_path,
        filename=f"{artifact.name}",
        media_type=artifact.mime_type or "application/octet-stream"
    )


@router.put("/artifacts/{artifact_id}", response_model=ArtifactResponse)
async def update_artifact(
    artifact_id: str,
    artifact_update: ArtifactCreate,
    db: Session = Depends(get_db)
):
    """Update an artifact"""
    
    artifact = db.query(Artifact).filter(
        Artifact.artifact_id == artifact_id
    ).first()
    
    if not artifact:
        raise HTTPException(status_code=404, detail="Artifact not found")
    
    storage_manager = get_storage_manager()
    
    try:
        # Update file content
        file_info = storage_manager.save_artifact_file(
            content=artifact_update.content,
            artifact_type=artifact.type,
            session_id=artifact.session_id,
            filename=artifact.name
        )
        
        # Update database record
        artifact.name = artifact_update.name
        artifact.description = artifact_update.description
        artifact.size_bytes = file_info["size_bytes"]
        artifact.custom_metadata = artifact_update.custom_metadata or {}
        
        db.commit()
        db.refresh(artifact)
        
        return ArtifactResponse(
            artifact_id=artifact.artifact_id,
            session_id=artifact.session_id,
            message_id=artifact.message_id,
            type=artifact.type,
            name=artifact.name,
            description=artifact.description,
            file_path=artifact.file_path,
            mime_type=artifact.mime_type,
            size_bytes=artifact.size_bytes,
            custom_metadata=artifact.custom_metadata,
            created_at=artifact.created_at
        )
        
    except Exception as e:
        logger.error(f"Failed to update artifact: {e}")
        raise HTTPException(status_code=500, detail="Failed to update artifact")


@router.delete("/artifacts/{artifact_id}")
async def delete_artifact(
    artifact_id: str,
    db: Session = Depends(get_db)
):
    """Delete an artifact"""
    
    artifact = db.query(Artifact).filter(
        Artifact.artifact_id == artifact_id
    ).first()
    
    if not artifact:
        raise HTTPException(status_code=404, detail="Artifact not found")
    
    storage_manager = get_storage_manager()
    
    # Delete file
    storage_manager.delete_artifact_file(artifact.file_path)
    
    # Delete database record
    db.delete(artifact)
    db.commit()
    
    return {"status": "deleted", "artifact_id": artifact_id}


@router.post("/artifacts/upload")
async def upload_artifact(
    session_id: str,
    artifact_type: str,
    name: str,
    file: UploadFile = File(...),
    description: Optional[str] = None,
    message_id: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Upload an artifact file"""
    
    artifact_id = str(uuid4())
    storage_manager = get_storage_manager()
    
    try:
        # Read file content
        content = await file.read()
        content_str = content.decode("utf-8")
        
        # Save file
        file_info = storage_manager.save_artifact_file(
            content=content_str,
            artifact_type=artifact_type,
            session_id=session_id,
            filename=file.filename or name
        )
        
        # Create database record
        artifact = Artifact(
            artifact_id=artifact_id,
            session_id=session_id,
            message_id=message_id,
            type=artifact_type,
            name=name,
            description=description,
            file_path=file_info["path"],
            mime_type=file.content_type or _get_mime_type(artifact_type),
            size_bytes=file_info["size_bytes"]
        )
        
        db.add(artifact)
        db.commit()
        db.refresh(artifact)
        
        return {
            "artifact_id": artifact_id,
            "name": name,
            "type": artifact_type,
            "size_bytes": file_info["size_bytes"]
        }
        
    except Exception as e:
        logger.error(f"Failed to upload artifact: {e}")
        raise HTTPException(status_code=500, detail="Failed to upload artifact")


def _get_mime_type(artifact_type: str) -> str:
    """Get MIME type for artifact type"""
    mime_types = {
        "code": "text/plain",
        "javascript": "application/javascript",
        "typescript": "application/typescript",
        "document": "text/markdown",
        "diagram": "image/svg+xml",
        "data": "application/json"
    }
    return mime_types.get(artifact_type, "text/plain")