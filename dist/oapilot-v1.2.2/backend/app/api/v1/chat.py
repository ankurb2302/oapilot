"""Chat API endpoints"""

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import uuid4
import time
import logging

from app.core.database import get_db
from app.core.llm_manager import get_llm_manager
from app.core.mcp_client import get_mcp_manager
from app.models.chat import ChatSession, ChatMessage
from app.models.schemas import (
    ChatSessionCreate, ChatSessionResponse, 
    ChatMessageCreate, ChatMessageResponse,
    QueryRequest, QueryResponse, QueryResult
)

logger = logging.getLogger(__name__)
router = APIRouter()

# In-memory query store for async processing
processing_queries = {}
completed_queries = {}


@router.post("/chat/sessions", response_model=ChatSessionResponse)
async def create_chat_session(
    session_create: ChatSessionCreate,
    db: Session = Depends(get_db)
):
    """Create a new chat session"""
    session_id = str(uuid4())
    
    # Create session in database
    session = ChatSession(
        session_id=session_id,
        title=session_create.title or f"Chat {session_id[:8]}",
        model_used=session_create.model
    )
    
    db.add(session)
    db.commit()
    db.refresh(session)
    
    return ChatSessionResponse(
        session_id=session.session_id,
        title=session.title,
        created_at=session.created_at,
        updated_at=session.updated_at,
        model_used=session.model_used
    )


@router.get("/chat/sessions", response_model=List[ChatSessionResponse])
async def list_chat_sessions(
    skip: int = 0,
    limit: int = 20,
    db: Session = Depends(get_db)
):
    """List all chat sessions"""
    sessions = db.query(ChatSession).offset(skip).limit(limit).all()
    
    return [
        ChatSessionResponse(
            session_id=session.session_id,
            title=session.title,
            created_at=session.created_at,
            updated_at=session.updated_at,
            model_used=session.model_used,
            message_count=len(session.messages),
            total_tokens=session.total_tokens or 0
        )
        for session in sessions
    ]


@router.get("/chat/sessions/{session_id}", response_model=ChatSessionResponse)
async def get_chat_session(
    session_id: str,
    db: Session = Depends(get_db)
):
    """Get a specific chat session"""
    session = db.query(ChatSession).filter(
        ChatSession.session_id == session_id
    ).first()
    
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    return ChatSessionResponse(
        session_id=session.session_id,
        title=session.title,
        created_at=session.created_at,
        updated_at=session.updated_at,
        model_used=session.model_used,
        message_count=len(session.messages),
        total_tokens=session.total_tokens or 0
    )


@router.get("/chat/sessions/{session_id}/messages", response_model=List[ChatMessageResponse])
async def get_session_messages(
    session_id: str,
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db)
):
    """Get messages for a chat session"""
    session = db.query(ChatSession).filter(
        ChatSession.session_id == session_id
    ).first()
    
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    messages = db.query(ChatMessage).filter(
        ChatMessage.session_id == session_id
    ).order_by(ChatMessage.timestamp).offset(skip).limit(limit).all()
    
    return [
        ChatMessageResponse(
            message_id=msg.message_id,
            session_id=msg.session_id,
            role=msg.role,
            content=msg.content,
            mcp_resources_used=msg.mcp_resources_used,
            timestamp=msg.timestamp,
            tokens_used=msg.tokens_used,
            processing_time=msg.processing_time
        )
        for msg in messages
    ]


@router.post("/chat/sessions/{session_id}/messages", response_model=ChatMessageResponse)
async def send_message(
    session_id: str,
    message_create: ChatMessageCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """Send a message in a chat session"""
    
    # Verify session exists
    session = db.query(ChatSession).filter(
        ChatSession.session_id == session_id
    ).first()
    
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Create user message
    user_message_id = str(uuid4())
    user_message = ChatMessage(
        message_id=user_message_id,
        session_id=session_id,
        role="user",
        content=message_create.content
    )
    
    db.add(user_message)
    db.commit()
    
    # Process query and generate response
    assistant_message_id = str(uuid4())
    
    # Start background processing
    background_tasks.add_task(
        process_message,
        session_id,
        assistant_message_id,
        message_create.content,
        message_create.use_mcp,
        message_create.mcp_servers,
        session.model_used or "phi3:mini"
    )
    
    # Return user message immediately
    return ChatMessageResponse(
        message_id=user_message_id,
        session_id=session_id,
        role="user",
        content=message_create.content,
        timestamp=user_message.timestamp
    )


async def process_message(
    session_id: str,
    message_id: str,
    content: str,
    use_mcp: bool,
    mcp_servers: Optional[List[str]],
    model: str
):
    """Process message and generate AI response"""
    start_time = time.time()
    
    try:
        # Get database session
        from app.core.database import SessionLocal
        db = SessionLocal()
        
        # Get LLM and MCP managers
        llm_manager = get_llm_manager()
        mcp_manager = get_mcp_manager()
        
        # Gather MCP resources if enabled
        mcp_resources = []
        if use_mcp:
            try:
                all_resources = await mcp_manager.get_all_resources()
                
                # Filter by specific servers if requested
                if mcp_servers:
                    for server_id in mcp_servers:
                        if server_id in all_resources:
                            mcp_resources.extend(all_resources[server_id])
                else:
                    # Use all available resources
                    for resources in all_resources.values():
                        mcp_resources.extend(resources)
                        
            except Exception as e:
                logger.error(f"Failed to get MCP resources: {e}")
        
        # Format prompt with context
        prompt = llm_manager.format_prompt(
            user_query=content,
            mcp_resources=mcp_resources[:10]  # Limit to prevent token overflow
        )
        
        # Generate response
        result = llm_manager.generate(
            prompt=prompt,
            model=model,
            max_tokens=512
        )
        
        processing_time = time.time() - start_time
        
        # Save assistant message
        assistant_message = ChatMessage(
            message_id=message_id,
            session_id=session_id,
            role="assistant",
            content=result["response"],
            mcp_resources_used={"resources": mcp_resources[:5]} if mcp_resources else None,
            tokens_used=result["tokens"],
            processing_time=processing_time
        )
        
        db.add(assistant_message)
        
        # Update session token count
        session = db.query(ChatSession).filter(
            ChatSession.session_id == session_id
        ).first()
        
        if session:
            session.total_tokens = (session.total_tokens or 0) + result["tokens"]["total"]
        
        db.commit()
        db.close()
        
        logger.info(f"Message processed in {processing_time:.2f}s")
        
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        
        # Save error response
        from app.core.database import SessionLocal
        db = SessionLocal()
        
        error_message = ChatMessage(
            message_id=message_id,
            session_id=session_id,
            role="assistant",
            content=f"I apologize, but I encountered an error processing your request: {str(e)}",
            processing_time=time.time() - start_time
        )
        
        db.add(error_message)
        db.commit()
        db.close()


@router.delete("/chat/sessions/{session_id}")
async def delete_chat_session(
    session_id: str,
    db: Session = Depends(get_db)
):
    """Delete a chat session and all its data"""
    session = db.query(ChatSession).filter(
        ChatSession.session_id == session_id
    ).first()
    
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    
    # Delete session (cascades to messages and artifacts)
    db.delete(session)
    db.commit()
    
    # TODO: Clean up artifact files
    # storage_manager = get_storage_manager()
    # storage_manager.delete_session_artifacts(session_id)
    
    return {"status": "deleted", "session_id": session_id}


# Simple query endpoint for direct queries
@router.post("/query", response_model=QueryResponse)
async def submit_query(
    query_request: QueryRequest,
    background_tasks: BackgroundTasks
):
    """Submit a direct query for processing"""
    query_id = str(uuid4())
    
    # Store query for processing
    processing_queries[query_id] = {
        "query": query_request.query,
        "session_id": query_request.session_id,
        "model": query_request.model or "phi3:mini",
        "use_mcp": query_request.use_mcp,
        "created_at": time.time()
    }
    
    # Start background processing
    background_tasks.add_task(process_direct_query, query_id)
    
    return QueryResponse(
        query_id=query_id,
        status="processing",
        created_at=time.time()
    )


@router.get("/query/{query_id}/status")
async def get_query_status(query_id: str):
    """Get the status of a query"""
    if query_id in completed_queries:
        return {"status": "completed", "query_id": query_id}
    elif query_id in processing_queries:
        return {"status": "processing", "query_id": query_id}
    else:
        raise HTTPException(status_code=404, detail="Query not found")


@router.get("/query/{query_id}/result", response_model=QueryResult)
async def get_query_result(query_id: str):
    """Get the result of a completed query"""
    if query_id not in completed_queries:
        raise HTTPException(status_code=404, detail="Query result not found")
    
    return completed_queries[query_id]


async def process_direct_query(query_id: str):
    """Process a direct query"""
    if query_id not in processing_queries:
        return
    
    query_data = processing_queries[query_id]
    start_time = time.time()
    
    try:
        llm_manager = get_llm_manager()
        mcp_manager = get_mcp_manager()
        
        # Get MCP resources if enabled
        mcp_resources = []
        if query_data["use_mcp"]:
            try:
                all_resources = await mcp_manager.get_all_resources()
                for resources in all_resources.values():
                    mcp_resources.extend(resources)
            except Exception as e:
                logger.error(f"Failed to get MCP resources: {e}")
        
        # Format and generate
        prompt = llm_manager.format_prompt(
            user_query=query_data["query"],
            mcp_resources=mcp_resources[:10]
        )
        
        result = llm_manager.generate(
            prompt=prompt,
            model=query_data["model"]
        )
        
        processing_time = time.time() - start_time
        
        # Store result
        completed_queries[query_id] = QueryResult(
            query_id=query_id,
            response=result["response"],
            mcp_resources_used=mcp_resources[:5] if mcp_resources else [],
            processing_time=processing_time,
            model_used=query_data["model"],
            tokens_used=result["tokens"],
            artifacts=[]  # TODO: Handle artifacts
        )
        
        # Remove from processing
        del processing_queries[query_id]
        
    except Exception as e:
        logger.error(f"Error processing direct query: {e}")
        
        completed_queries[query_id] = QueryResult(
            query_id=query_id,
            response=f"Error processing query: {str(e)}",
            mcp_resources_used=[],
            processing_time=time.time() - start_time,
            model_used=query_data["model"],
            tokens_used={"prompt": 0, "response": 0, "total": 0},
            artifacts=[]
        )
        
        del processing_queries[query_id]