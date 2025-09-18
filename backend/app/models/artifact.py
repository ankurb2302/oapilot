"""Artifact model for storing generated content"""

from sqlalchemy import Column, Integer, String, DateTime, Text, ForeignKey, JSON
from sqlalchemy.orm import relationship
from datetime import datetime

from app.core.database import Base


class Artifact(Base):
    """Artifact model for storing generated files and content"""
    __tablename__ = "artifacts"
    
    id = Column(Integer, primary_key=True, index=True)
    artifact_id = Column(String(36), unique=True, index=True, nullable=False)
    session_id = Column(String(36), ForeignKey("chat_sessions.session_id", ondelete="CASCADE"))
    message_id = Column(String(36), ForeignKey("chat_messages.message_id", ondelete="CASCADE"))
    type = Column(String(50), nullable=False)  # "code", "document", "diagram", "data"
    name = Column(String(200), nullable=False)
    description = Column(Text)
    file_path = Column(String(500))
    mime_type = Column(String(100))
    size_bytes = Column(Integer)
    custom_metadata = Column(JSON)
    created_at = Column(DateTime, default=datetime.utcnow)
    
    # Relationships
    session = relationship("ChatSession", back_populates="artifacts")
    
    def __repr__(self):
        return f"<Artifact(artifact_id={self.artifact_id}, type={self.type}, name={self.name})>"