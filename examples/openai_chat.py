"""
Example code for interacting with model served by vLLM.

For information about the OpenAI Python API library, see:
    https://github.com/openai/openai-python
"""
import os
import re
import socket
import sys
import time

from openai import APIConnectionError, OpenAI


def _get_hostname():
    """
    Return hostname, setting to 'localhost' if associated IP address not found.
    """
    hostname = socket.gethostname()
    try:
        socket.gethostbyname(hostname)
    except socket.gaierror:
        hostname = "localhost"
    return hostname


def can_connect(client, interval=60, max_wait=1200, verbose=True):
    """
    Check whether connection to client can be established.

    With the specified interval between them, attempts to connect to the
    client are repeated until either an attempt is successful (return True)
    of the time elapsed since the first attempt exceeds max_wait (return False).
    Progress information is printed if the verbose parameter is set to True.
    """
    wait_time = 0
    while True:
        try:
            client.models.list()
            if verbose:
                print("Connected to vLLM server.\n", flush=True)
            return True
        except APIConnectionError:
            if verbose:
                print("Unable to connect to vLLM server:")
            status = f"    wait time: {wait_time} s; max wait: {max_wait} s"
            if wait_time >= max_wait:
                if verbose:
                    print(f"{status}; exiting")
                    return False
            else:
                if verbose:
                    print(f"{status}; retry in {interval} s", flush=True)
                wait_time += interval
                time.sleep(interval)
                      

def get_base_url(default_vllm_host=_get_hostname() , default_vllm_port="8000"):
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
    print(f"{history[-1]['role']}:\n{history[-1]['content']}\n", flush=True)


# Create OpenAI client.
client = OpenAI(base_url=get_base_url())
if not can_connect(client):
    sys.exit(1)

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
