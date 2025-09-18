"""Memory-optimized LLM manager using Ollama"""

import ollama
from typing import Optional, Dict, Generator, List, Any
import psutil
import gc
import logging
import time
from datetime import datetime

from app.core.config import settings

logger = logging.getLogger(__name__)


class OptimizedLLMManager:
    """Memory-optimized LLM manager for resource-constrained environments"""
    
    # Recommended models for 8GB RAM systems
    LIGHTWEIGHT_MODELS = {
        "phi3:mini": {
            "size_gb": 2.0,
            "context": 2048,
            "description": "Microsoft Phi-3 Mini - Best for limited RAM"
        },
        "gemma:2b": {
            "size_gb": 1.5,
            "context": 2048,
            "description": "Google Gemma 2B - Fastest inference"
        },
        "qwen2:1.5b": {
            "size_gb": 1.0,
            "context": 2048,
            "description": "Qwen 1.5B - Minimal memory usage"
        },
        "mistral:7b-instruct-q4_0": {
            "size_gb": 3.8,
            "context": 4096,
            "description": "Mistral 7B Quantized - Best quality if RAM allows"
        }
    }
    
    def __init__(self):
        self.current_model = None
        self.model_name = settings.LLM_MODEL
        self.ollama_host = settings.OLLAMA_HOST
        self.client = ollama.Client(host=self.ollama_host)
        self._initialize()
    
    def _initialize(self):
        """Initialize the LLM manager"""
        try:
            # Check if Ollama is running
            self.client.list()
            logger.info(f"Connected to Ollama at {self.ollama_host}")
        except Exception as e:
            logger.error(f"Failed to connect to Ollama: {e}")
            raise ConnectionError(f"Cannot connect to Ollama at {self.ollama_host}. Ensure Ollama is running.")
    
    def check_memory(self) -> Dict[str, float]:
        """Check available system memory"""
        mem = psutil.virtual_memory()
        return {
            "total_gb": mem.total / (1024**3),
            "available_gb": mem.available / (1024**3),
            "used_gb": mem.used / (1024**3),
            "percent": mem.percent
        }
    
    def list_available_models(self) -> List[Dict[str, Any]]:
        """List models available in Ollama"""
        try:
            models = self.client.list()
            return [
                {
                    "name": model.get("name"),
                    "size": model.get("size", 0) / (1024**3),  # Convert to GB
                    "modified": model.get("modified_at")
                }
                for model in models.get("models", [])
            ]
        except Exception as e:
            logger.error(f"Failed to list models: {e}")
            return []
    
    def ensure_model(self, model_name: Optional[str] = None) -> bool:
        """Ensure model is available, pull if needed"""
        model = model_name or self.model_name
        
        try:
            # Check if model exists
            models = self.list_available_models()
            if any(m["name"] == model for m in models):
                self.current_model = model
                return True
            
            # Check memory before pulling
            mem = self.check_memory()
            model_info = self.LIGHTWEIGHT_MODELS.get(model, {})
            required_gb = model_info.get("size_gb", 4.0)
            
            if mem["available_gb"] < required_gb + 1:  # +1GB buffer
                raise MemoryError(
                    f"Insufficient memory to load {model}. "
                    f"Need {required_gb+1:.1f}GB, have {mem['available_gb']:.1f}GB available"
                )
            
            # Pull the model
            logger.info(f"Pulling model {model}...")
            self.client.pull(model)
            self.current_model = model
            logger.info(f"Model {model} ready")
            return True
            
        except Exception as e:
            logger.error(f"Failed to ensure model {model}: {e}")
            return False
    
    def generate(
        self,
        prompt: str,
        model: Optional[str] = None,
        max_tokens: Optional[int] = None,
        temperature: float = 0.7,
        stream: bool = False,
        context: Optional[List[int]] = None
    ) -> Dict[str, Any]:
        """Generate response with memory management"""
        
        # Ensure model is loaded
        model_to_use = model or self.current_model or self.model_name
        if not self.ensure_model(model_to_use):
            raise RuntimeError(f"Model {model_to_use} not available")
        
        # Force garbage collection before generation
        gc.collect()
        
        # Prepare generation parameters
        options = {
            "num_ctx": settings.LLM_CONTEXT_SIZE,
            "num_predict": max_tokens or settings.LLM_MAX_TOKENS,
            "temperature": temperature,
            "num_thread": settings.LLM_NUM_THREADS,
            "num_batch": settings.LLM_BATCH_SIZE,
            "use_mmap": settings.LLM_USE_MMAP,
            "use_mlock": settings.LLM_USE_MLOCK,
        }
        
        try:
            start_time = time.time()
            
            if stream:
                return self._generate_stream(model_to_use, prompt, options, context)
            
            # Non-streaming generation
            response = self.client.generate(
                model=model_to_use,
                prompt=prompt,
                options=options,
                context=context,
                stream=False
            )
            
            processing_time = time.time() - start_time
            
            return {
                "response": response.get("response", ""),
                "model": model_to_use,
                "tokens": {
                    "prompt": response.get("prompt_eval_count", 0),
                    "response": response.get("eval_count", 0),
                    "total": response.get("prompt_eval_count", 0) + response.get("eval_count", 0)
                },
                "processing_time": processing_time,
                "context": response.get("context", [])
            }
            
        except Exception as e:
            logger.error(f"Generation failed: {e}")
            raise
        finally:
            # Clean up after generation
            gc.collect()
    
    def _generate_stream(
        self,
        model: str,
        prompt: str,
        options: Dict,
        context: Optional[List[int]]
    ) -> Generator[str, None, None]:
        """Stream generation with memory management"""
        try:
            stream = self.client.generate(
                model=model,
                prompt=prompt,
                options=options,
                context=context,
                stream=True
            )
            
            for chunk in stream:
                if "response" in chunk:
                    yield chunk["response"]
                    
        except Exception as e:
            logger.error(f"Stream generation failed: {e}")
            raise
        finally:
            gc.collect()
    
    def format_prompt(
        self,
        user_query: str,
        context: Optional[str] = None,
        mcp_resources: Optional[List[Dict]] = None
    ) -> str:
        """Format prompt with context and MCP resources"""
        
        prompt_parts = []
        
        # System instruction
        prompt_parts.append(
            "You are OAPilot, an AI assistant with access to organizational tools through MCP servers. "
            "Provide helpful, accurate, and concise responses."
        )
        
        # Add MCP context if available
        if mcp_resources:
            prompt_parts.append("\nAvailable MCP Resources:")
            for resource in mcp_resources:
                prompt_parts.append(f"- {resource.get('name', 'Unknown')}: {resource.get('description', '')}")
        
        # Add additional context
        if context:
            prompt_parts.append(f"\nContext:\n{context}")
        
        # Add user query
        prompt_parts.append(f"\nUser Query: {user_query}")
        prompt_parts.append("\nResponse:")
        
        return "\n".join(prompt_parts)
    
    def unload_model(self):
        """Unload model to free memory"""
        self.current_model = None
        gc.collect()
        logger.info("Model unloaded, memory freed")
    
    def get_model_info(self, model_name: Optional[str] = None) -> Dict[str, Any]:
        """Get information about a model"""
        model = model_name or self.current_model or self.model_name
        
        # Check predefined info
        if model in self.LIGHTWEIGHT_MODELS:
            return self.LIGHTWEIGHT_MODELS[model]
        
        # Try to get from Ollama
        try:
            models = self.list_available_models()
            for m in models:
                if m["name"] == model:
                    return {
                        "name": model,
                        "size_gb": m["size"],
                        "context": settings.LLM_CONTEXT_SIZE,
                        "description": "Custom model"
                    }
        except Exception as e:
            logger.error(f"Failed to get model info: {e}")
        
        return {
            "name": model,
            "size_gb": 0,
            "context": settings.LLM_CONTEXT_SIZE,
            "description": "Unknown model"
        }


# Global instance
llm_manager = None


def get_llm_manager() -> OptimizedLLMManager:
    """Get or create LLM manager instance"""
    global llm_manager
    if llm_manager is None:
        llm_manager = OptimizedLLMManager()
    return llm_manager