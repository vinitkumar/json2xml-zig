#!/usr/bin/env python3
"""
Benchmark script for json2xml-zig vs json2xml-go vs json2xml-py.

Compares performance of Zig, Go, and Python implementations across
different JSON sizes.

Environment variables:
    JSON2XML_GO_CLI: Path to the json2xml-go binary
    JSON2XML_ZIG_CLI: Path to the json2xml-zig binary
    JSON2XML_EXAMPLES_DIR: Path to examples directory
"""
from __future__ import annotations

import json
import os
import random
import string
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Base directory for repo-relative defaults
BASE_DIR = Path(__file__).resolve().parent

# Paths - configurable via environment variables
PYTHON_CLI = [sys.executable, "-m", "json2xml.cli"]
GO_CLI = Path(os.environ.get("JSON2XML_GO_CLI", os.path.expanduser("~/projects/go/json2xml-go/json2xml-go")))
ZIG_CLI = Path(os.environ.get("JSON2XML_ZIG_CLI", str(BASE_DIR / "zig-out" / "bin" / "json2xml-zig")))
EXAMPLES_DIR = Path(os.environ.get("JSON2XML_EXAMPLES_DIR", os.path.expanduser("~/projects/python/json2xml/examples")))


# Colors for terminal output
class Colors:
    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    BLUE = "\033[0;34m"
    YELLOW = "\033[1;33m"
    CYAN = "\033[0;36m"
    MAGENTA = "\033[0;35m"
    BOLD = "\033[1m"
    NC = "\033[0m"  # No Color


def colorize(text: str, color: str) -> str:
    """Wrap text in color codes."""
    return f"{color}{text}{Colors.NC}"


def random_string(length: int = 10) -> str:
    """Generate a random string."""
    return "".join(random.choices(string.ascii_letters, k=length))


def generate_large_json(num_records: int = 1000) -> str:
    """Generate a large JSON file for benchmarking."""
    data = []
    for i in range(num_records):
        item = {
            "id": i,
            "name": random_string(20),
            "email": f"{random_string(8)}@example.com",
            "active": random.choice([True, False]),
            "score": round(random.uniform(0, 100), 2),
            "tags": [random_string(5) for _ in range(5)],
            "metadata": {
                "created": "2024-01-15T10:30:00Z",
                "updated": "2024-01-15T12:45:00Z",
                "version": random.randint(1, 100),
                "nested": {
                    "level1": {
                        "level2": {"value": random_string(10)}
                    }
                },
            },
        }
        data.append(item)
    return json.dumps(data)


def run_benchmark(
    cmd: list[str],
    iterations: int = 10,
    warmup: int = 2
) -> dict[str, float]:
    """
    Run a benchmark for the given command.

    Returns dict with avg, min, max times in milliseconds.
    """
    times = []

    # Warmup runs
    for _ in range(warmup):
        subprocess.run(cmd, capture_output=True, check=False)

    # Timed runs
    for _ in range(iterations):
        start = time.perf_counter()
        result = subprocess.run(cmd, capture_output=True, check=False)
        end = time.perf_counter()

        if result.returncode != 0:
            print(f"Error: {result.stderr.decode()}")
            continue

        duration_ms = (end - start) * 1000
        times.append(duration_ms)

    if not times:
        return {"avg": 0, "min": 0, "max": 0}

    return {
        "avg": sum(times) / len(times),
        "min": min(times),
        "max": max(times),
    }


def format_time(ms: float) -> str:
    """Format time in milliseconds."""
    if ms < 1:
        return f"{ms * 1000:.2f}µs"
    elif ms < 1000:
        return f"{ms:.2f}ms"
    else:
        return f"{ms / 1000:.2f}s"


def print_header(title: str) -> None:
    """Print a section header."""
    print(colorize("=" * 60, Colors.BLUE))
    print(colorize(f"  {title}", Colors.BOLD))
    print(colorize("=" * 60, Colors.BLUE))


def print_result(name: str, result: dict[str, float], color: str = Colors.NC) -> None:
    """Print benchmark result."""
    print(f"  {colorize(name, color)}:")
    print(f"    Avg: {format_time(result['avg'])} | "
          f"Min: {format_time(result['min'])} | "
          f"Max: {format_time(result['max'])}")


def main() -> int:
    """Run the benchmark suite."""
    print_header("json2xml Benchmark: Python vs Go vs Zig")
    print()

    # Check prerequisites
    print(colorize("Checking prerequisites...", Colors.YELLOW))

    # Check Python json2xml
    try:
        result = subprocess.run(
            [sys.executable, "-c", "import json2xml; print('ok')"],
            capture_output=True, check=True
        )
        print(colorize("✓ Python json2xml found", Colors.GREEN))
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(colorize("✗ Python json2xml not found. Install with: pip install json2xml", Colors.RED))
        return 1

    # Check Go binary
    if not GO_CLI.exists():
        print(colorize(f"✗ Go binary not found at {GO_CLI}", Colors.RED))
        print("  Please build it first: cd ~/projects/go/json2xml-go && make")
        go_available = False
    else:
        print(colorize(f"✓ Go binary found at {GO_CLI}", Colors.GREEN))
        go_available = True

    # Check Zig binary
    if not ZIG_CLI.exists():
        print(colorize(f"✗ Zig binary not found at {ZIG_CLI}", Colors.RED))
        print("  Building Zig binary...")
        result = subprocess.run(
            ["zig", "build", "-Doptimize=ReleaseFast"],
            cwd=BASE_DIR,
            capture_output=True
        )
        if result.returncode != 0:
            print(colorize(f"  Failed to build: {result.stderr.decode()}", Colors.RED))
            return 1
        print(colorize("✓ Zig binary built successfully", Colors.GREEN))
    else:
        print(colorize(f"✓ Zig binary found at {ZIG_CLI}", Colors.GREEN))

    print()

    # Test configurations
    iterations = 10
    results = {}

    # Create temp files for testing
    with tempfile.TemporaryDirectory() as tmpdir:
        # Small JSON - inline string
        small_json = '{"name": "John", "age": 30, "city": "New York"}'

        # Medium JSON - existing file
        medium_json_file = EXAMPLES_DIR / "bigexample.json"
        if not medium_json_file.exists():
            print(colorize(f"Warning: {medium_json_file} not found, skipping medium test", Colors.YELLOW))
            medium_json_file = None

        # Large JSON - generated
        large_json = generate_large_json(1000)
        large_json_file = Path(tmpdir) / "large.json"
        large_json_file.write_text(large_json)

        # Very large JSON
        very_large_json = generate_large_json(5000)
        very_large_json_file = Path(tmpdir) / "very_large.json"
        very_large_json_file.write_text(very_large_json)

        print(colorize("Test file sizes:", Colors.CYAN))
        print(f"  Small:      {len(small_json)} bytes (inline)")
        if medium_json_file:
            print(f"  Medium:     {medium_json_file.stat().st_size:,} bytes")
        print(f"  Large:      {large_json_file.stat().st_size:,} bytes (1000 records)")
        print(f"  Very Large: {very_large_json_file.stat().st_size:,} bytes (5000 records)")
        print()

        # Benchmark: Small JSON (inline string)
        print(colorize("--- Small JSON (inline string) ---", Colors.BLUE))
        py_small = run_benchmark(PYTHON_CLI + ["-s", small_json], iterations)
        print_result("Python", py_small, Colors.YELLOW)
        
        if go_available:
            go_small = run_benchmark([str(GO_CLI), "-s", small_json], iterations)
            print_result("Go", go_small, Colors.CYAN)
        else:
            go_small = {"avg": 0, "min": 0, "max": 0}
            
        zig_small = run_benchmark([str(ZIG_CLI), "-s", small_json], iterations)
        print_result("Zig", zig_small, Colors.MAGENTA)
        results["small"] = {"python": py_small, "go": go_small, "zig": zig_small}
        print()

        # Benchmark: Medium JSON (file)
        if medium_json_file:
            print(colorize("--- Medium JSON (bigexample.json) ---", Colors.BLUE))
            py_medium = run_benchmark(PYTHON_CLI + [str(medium_json_file)], iterations)
            print_result("Python", py_medium, Colors.YELLOW)
            
            if go_available:
                go_medium = run_benchmark([str(GO_CLI), str(medium_json_file)], iterations)
                print_result("Go", go_medium, Colors.CYAN)
            else:
                go_medium = {"avg": 0, "min": 0, "max": 0}
                
            zig_medium = run_benchmark([str(ZIG_CLI), str(medium_json_file)], iterations)
            print_result("Zig", zig_medium, Colors.MAGENTA)
            results["medium"] = {"python": py_medium, "go": go_medium, "zig": zig_medium}
            print()

        # Benchmark: Large JSON (file)
        print(colorize("--- Large JSON (1000 records) ---", Colors.BLUE))
        py_large = run_benchmark(PYTHON_CLI + [str(large_json_file)], iterations)
        print_result("Python", py_large, Colors.YELLOW)
        
        if go_available:
            go_large = run_benchmark([str(GO_CLI), str(large_json_file)], iterations)
            print_result("Go", go_large, Colors.CYAN)
        else:
            go_large = {"avg": 0, "min": 0, "max": 0}
            
        zig_large = run_benchmark([str(ZIG_CLI), str(large_json_file)], iterations)
        print_result("Zig", zig_large, Colors.MAGENTA)
        results["large"] = {"python": py_large, "go": go_large, "zig": zig_large}
        print()

        # Benchmark: Very Large JSON (file)
        print(colorize("--- Very Large JSON (5000 records) ---", Colors.BLUE))
        py_vlarge = run_benchmark(PYTHON_CLI + [str(very_large_json_file)], iterations)
        print_result("Python", py_vlarge, Colors.YELLOW)
        
        if go_available:
            go_vlarge = run_benchmark([str(GO_CLI), str(very_large_json_file)], iterations)
            print_result("Go", go_vlarge, Colors.CYAN)
        else:
            go_vlarge = {"avg": 0, "min": 0, "max": 0}
            
        zig_vlarge = run_benchmark([str(ZIG_CLI), str(very_large_json_file)], iterations)
        print_result("Zig", zig_vlarge, Colors.MAGENTA)
        results["very_large"] = {"python": py_vlarge, "go": go_vlarge, "zig": zig_vlarge}
        print()

    # Summary
    print_header("SUMMARY")
    print()

    for size, data in results.items():
        py_avg = data["python"]["avg"]
        go_avg = data["go"]["avg"]
        zig_avg = data["zig"]["avg"]

        print(colorize(f"{size.replace('_', ' ').title()} JSON:", Colors.BOLD))
        print(f"  {colorize('Python', Colors.YELLOW)}: {format_time(py_avg)}")
        
        if go_avg > 0:
            print(f"  {colorize('Go', Colors.CYAN)}:     {format_time(go_avg)}")
            go_speedup = py_avg / go_avg if go_avg > 0 else 0
            print(f"         Go is {colorize(f'{go_speedup:.1f}x faster', Colors.GREEN)} than Python")
        
        print(f"  {colorize('Zig', Colors.MAGENTA)}:    {format_time(zig_avg)}")
        zig_speedup = py_avg / zig_avg if zig_avg > 0 else 0
        print(f"         Zig is {colorize(f'{zig_speedup:.1f}x faster', Colors.GREEN)} than Python")
        
        if go_avg > 0 and zig_avg > 0:
            zig_vs_go = go_avg / zig_avg
            if zig_vs_go > 1:
                print(f"         Zig is {colorize(f'{zig_vs_go:.1f}x faster', Colors.GREEN)} than Go")
            else:
                print(f"         Go is {colorize(f'{1/zig_vs_go:.1f}x faster', Colors.CYAN)} than Zig")
        print()

    # Overall average speedup
    total_py = sum(r["python"]["avg"] for r in results.values())
    total_go = sum(r["go"]["avg"] for r in results.values() if r["go"]["avg"] > 0)
    total_zig = sum(r["zig"]["avg"] for r in results.values())
    
    print(colorize("Overall Performance:", Colors.BOLD))
    if total_go > 0:
        overall_go_speedup = total_py / total_go
        print(f"  Go is {colorize(f'{overall_go_speedup:.1f}x faster', Colors.CYAN)} than Python")
    
    if total_zig > 0:
        overall_zig_speedup = total_py / total_zig
        print(f"  Zig is {colorize(f'{overall_zig_speedup:.1f}x faster', Colors.MAGENTA)} than Python")
        
        if total_go > 0:
            zig_vs_go_overall = total_go / total_zig
            if zig_vs_go_overall > 1:
                print(f"  Zig is {colorize(f'{zig_vs_go_overall:.1f}x faster', Colors.MAGENTA)} than Go")
            else:
                print(f"  Go is {colorize(f'{1/zig_vs_go_overall:.1f}x faster', Colors.CYAN)} than Zig")

    print()
    print(colorize("=" * 60, Colors.BLUE))
    print(colorize("Benchmark complete!", Colors.GREEN))
    print(colorize("=" * 60, Colors.BLUE))

    return 0


if __name__ == "__main__":
    sys.exit(main())
