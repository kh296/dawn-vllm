"""
Example code for interacting with model served by vLLM.

For information about the OpenAI Python API library, see:
    https://github.com/openai/openai-python
"""
from openai import OpenAI
import os
import re
import socket

def get_base_url(
    default_vllm_host=socket.gethostname(), default_vllm_port="8000"):
    """
    Return URL that can be used with OpenAI client.

    The host and client components are set from environment variables,
    if defined, or otherwise are set to default values.
    """
    vllm_host = os.environ.get("VLLM_HOST", default_vllm_host)
    vllm_port = os.environ.get("VLLM_PORT", default_vllm_port)
    return f"http://{vllm_host}:{vllm_port}/v1"

def no_think_block(text):
    """
    Return input text with any think block(s) removed.

    A think block may be included, for example, in an OpenAI response.
    """
    return re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()

def print_latest(history):
    """
    Return formatted output for last item in input history list.

    Each history item is assumed to be a dictionary
    with keys "role" and "content", such as used in OpenAI messages.
    """
    print(f"{history[-1]['role']}:\n{history[-1]['content']}\n")

# Create OpenAI client.
client = OpenAI(base_url=get_base_url())

# Initialise message history.
history = [{"role": "system", "content": "You are an expert coder."}]
print_latest(history)

# Obtain and record first OpenAI response.
history.append({"role": "user", "content":
    ("Suggest an exercise, and its solution, for "
     "students who have completed an intermediate-level Python course.")})
print_latest(history)

response = client.responses.create(
    input = history,
    store = False,
    )

assistant_content = no_think_block(response.output_text)
history.append({"role": "assistant", "content": assistant_content})
print_latest(history)

# Obtain and record second OpenAI response.
history.append({"role": "user",
    "content": "Suggest a second exercise and its solution."})
print_latest(history)

response = client.responses.create(
    input = history,
    store = False,
    )

assistant_content = no_think_block(response.output_text)
history.append({"role": "assistant", "content": assistant_content})
print_latest(history)
