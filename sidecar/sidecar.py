#!/usr/bin/env python3
"""
VoiceGenius Sidecar Server
Runs on host Mac to provide LLM inference for iOS Simulator.
"""

from flask import Flask, request, jsonify
from mlx_lm import load, generate

app = Flask(__name__)

# Load model once at startup
print("Loading Sidecar Model...")
model, tokenizer = load("mlx-community/Llama-3.2-1B-Instruct-4bit")
print("Model loaded successfully!")


@app.route('/chat', methods=['POST'])
def chat():
    """Handle chat requests from iOS Simulator."""
    data = request.json
    prompt = data.get("prompt", "")

    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400

    # Format as chat message
    messages = [{"role": "user", "content": prompt}]
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
        max_tokens=256,
        verbose=True
    )

    return jsonify({"response": response_text})


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({"status": "ok", "model": "Llama-3.2-1B-Instruct-4bit"})


if __name__ == '__main__':
    # Bind to 0.0.0.0 to allow Simulator bridge access
    print("Starting sidecar server on http://0.0.0.0:8080")
    app.run(host='0.0.0.0', port=8080, debug=False)
