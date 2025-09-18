#!/usr/bin/env python3
"""
Simple MCP Server for testing
Implements basic JSON-RPC MCP protocol over STDIO
"""
import json
import sys
import logging

# Setup basic logging to stderr so it doesn't interfere with stdout
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)

class SimpleMCPServer:
    def __init__(self):
        self.name = "simple-mcp-server"
        self.version = "1.0.0"

    def handle_initialize(self, params):
        """Handle MCP initialize request"""
        logger.info(f"Initialize request: {params}")
        return {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {
                    "listChanged": True
                },
                "resources": {
                    "subscribe": True,
                    "listChanged": True
                }
            },
            "serverInfo": {
                "name": self.name,
                "version": self.version
            }
        }

    def handle_tools_list(self, params):
        """Handle tools/list request"""
        logger.info("Tools list request")
        return {
            "tools": [
                {
                    "name": "echo",
                    "description": "Echo back the input text",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "text": {
                                "type": "string",
                                "description": "Text to echo back"
                            }
                        },
                        "required": ["text"]
                    }
                }
            ]
        }

    def handle_tools_call(self, params):
        """Handle tools/call request"""
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        logger.info(f"Tool call: {tool_name} with args: {arguments}")

        if tool_name == "echo":
            text = arguments.get("text", "No text provided")
            return {
                "content": [
                    {
                        "type": "text",
                        "text": f"Echo: {text}"
                    }
                ]
            }
        else:
            raise ValueError(f"Unknown tool: {tool_name}")

    def handle_resources_list(self, params):
        """Handle resources/list request"""
        logger.info("Resources list request")
        return {
            "resources": [
                {
                    "uri": "test://example",
                    "name": "Example Resource",
                    "description": "A simple test resource",
                    "mimeType": "text/plain"
                }
            ]
        }

    def handle_request(self, request):
        """Handle incoming JSON-RPC request"""
        try:
            method = request.get("method")
            params = request.get("params", {})
            request_id = request.get("id")

            logger.info(f"Handling method: {method}")

            # Route to appropriate handler
            if method == "initialize":
                result = self.handle_initialize(params)
            elif method == "tools/list":
                result = self.handle_tools_list(params)
            elif method == "tools/call":
                result = self.handle_tools_call(params)
            elif method == "resources/list":
                result = self.handle_resources_list(params)
            else:
                raise ValueError(f"Unknown method: {method}")

            # Return success response
            response = {
                "jsonrpc": "2.0",
                "id": request_id,
                "result": result
            }

        except Exception as e:
            logger.error(f"Error handling request: {e}")
            # Return error response
            response = {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "error": {
                    "code": -32603,
                    "message": str(e)
                }
            }

        return response

    def run(self):
        """Main server loop - read from stdin, write to stdout"""
        logger.info("Starting Simple MCP Server")

        try:
            # Process requests line by line
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue

                try:
                    # Parse JSON-RPC request
                    request = json.loads(line)
                    logger.info(f"Received request: {request}")

                    # Handle request
                    response = self.handle_request(request)

                    # Send response
                    response_json = json.dumps(response)
                    print(response_json, flush=True)
                    logger.info(f"Sent response: {response}")

                except json.JSONDecodeError as e:
                    logger.error(f"Invalid JSON: {e}")
                    # Send error response
                    error_response = {
                        "jsonrpc": "2.0",
                        "id": None,
                        "error": {
                            "code": -32700,
                            "message": "Parse error"
                        }
                    }
                    print(json.dumps(error_response), flush=True)

        except KeyboardInterrupt:
            logger.info("Server stopped by user")
        except Exception as e:
            logger.error(f"Server error: {e}")

if __name__ == "__main__":
    server = SimpleMCPServer()
    server.run()