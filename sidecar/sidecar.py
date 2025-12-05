#!/usr/bin/env python3
"""
VoiceGenius Sidecar Server
Runs on host Mac to provide LLM inference for iOS Simulator.
"""

import json
from pathlib import Path
from flask import Flask, request, jsonify
from mlx_lm import load, generate

app = Flask(__name__)

# Load config from parent directory
config_path = Path(__file__).parent.parent / "config.json"
with open(config_path) as f:
    config = json.load(f)

MODEL_NAME = config["model"]
MAX_TOKENS = config.get("max_tokens", 256)
SYSTEM_PROMPT = config.get("system_prompt", "")

# Load model once at startup
print(f"Loading model: {MODEL_NAME}")
model, tokenizer = load(MODEL_NAME)
print("Model loaded successfully!")


@app.route('/chat', methods=['POST'])
def chat():
    """Handle chat requests from iOS Simulator."""
    data = request.json
    prompt = data.get("prompt", "")

    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400

    # Build messages with optional system prompt
    messages = []
    if SYSTEM_PROMPT:
        messages.append({"role": "system", "content": SYSTEM_PROMPT})
    messages.append({"role": "user", "content": prompt})

    formatted_prompt = tokenizer.apply_chat_template(
        messages,
        tokenize=False,
        add_generation_prompt=True
    )

    # Generate response
    response_text = generate(
        model,
        tokenizer,
        prompt=formatted_prompt,
        max_tokens=MAX_TOKENS,
        verbose=True
    )

    return jsonify({"response": response_text})


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    model_name = MODEL_NAME.split("/")[-1]  # Just the name part
    return jsonify({"status": "ok", "model": model_name})


if __name__ == '__main__':
    # Bind to 0.0.0.0 to allow Simulator bridge access
    print("Starting sidecar server on http://0.0.0.0:8080")
    app.run(host='0.0.0.0', port=8080, debug=False)
