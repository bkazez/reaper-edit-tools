#!/usr/bin/env python3
"""
Automix solver - computes optimal fader levels.
Run from command line, outputs JSON that automix.lua reads.

Usage: python3 automix_solve.py <spec_file> <track_list_file> <output_file>

track_list_file contains one track name per line (from REAPER).
output_file will contain JSON with fader levels.
"""

import sys
import json
import re
import numpy as np
from scipy.optimize import minimize


def db_to_linear(db):
    return 10 ** (db / 20)


def linear_to_db(lin):
    if lin <= 0:
        return -150
    return 20 * np.log10(lin)


def parse_nested_target(lines, start_idx):
    instruments = []
    target_weights = {}
    i = start_idx
    current_instrument = None
    current_instrument_weight = 0
    base_indent = None

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            i += 1
            continue

        indent = len(line) - len(line.lstrip())

        if base_indent is None:
            base_indent = indent

        if indent < base_indent and stripped:
            break

        match = re.match(r"(\w+):\s*([0-9.]+)\s*$", stripped)
        if match and indent == base_indent:
            current_instrument = match.group(1)
            current_instrument_weight = float(match.group(2))
            instruments.append(current_instrument)
            target_weights[current_instrument] = {"weight": current_instrument_weight}
            i += 1
            continue

        match = re.match(r"(direct|early):\s*([0-9.]+)\s*$", stripped)
        if match and current_instrument and indent > base_indent:
            type_name = match.group(1)
            type_weight = float(match.group(2))
            target_weights[current_instrument][type_name] = type_weight
            i += 1
            continue

        i += 1

    return instruments, target_weights, i


def parse_signal_components(component_str, signal_name, component_index):
    result = {}
    for part in component_str.split(","):
        part = part.strip()
        match = re.match(r"([0-9.]+)\s+(\S+)", part)
        if match:
            weight = float(match.group(1))
            name = match.group(2)
            if name == "direct":
                name = f"{signal_name}_direct"
            if name in component_index:
                result[component_index[name]] = weight
    return result


def parse_nested_signal(lines, start_idx, component_index):
    """Parse nested signal format like target format."""
    weights = {}
    i = start_idx
    current_instrument = None
    current_instrument_weight = 0
    base_indent = None

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            i += 1
            continue

        indent = len(line) - len(line.lstrip())

        if base_indent is None:
            base_indent = indent

        if indent < base_indent and stripped:
            break

        # Instrument line: "voc: 0.65"
        match = re.match(r"(\w+):\s*([0-9.]+)\s*$", stripped)
        if match and indent == base_indent:
            current_instrument = match.group(1)
            current_instrument_weight = float(match.group(2))
            i += 1
            continue

        # Component line: "direct: 0.9" or "early: 0.1"
        match = re.match(r"(direct|early):\s*([0-9.]+)\s*$", stripped)
        if match and current_instrument and indent > base_indent:
            comp_type = match.group(1)
            comp_weight = float(match.group(2))
            comp_name = f"{current_instrument}_{comp_type}"
            if comp_name in component_index:
                weights[component_index[comp_name]] = current_instrument_weight * comp_weight
            i += 1
            continue

        i += 1

    return weights, i


def parse_spec_file(filepath):
    with open(filepath, "r") as f:
        lines = f.readlines()

    instruments = []
    target_weights = {}
    hall_gain_db = 0.0
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped == "target:":
            instruments, target_weights, i = parse_nested_target(lines, i + 1)
            continue

        match = re.match(r"hall\s+gain:\s*(-?[0-9.]+)\s*$", stripped)
        if match:
            hall_gain_db = float(match.group(1))
            i += 1
            continue

        i += 1

    if not instruments:
        return None, "No target section found in spec file"

    components = []
    for instr in instruments:
        components.append(f"{instr}_direct")
        components.append(f"{instr}_early")
    component_index = {name: idx for idx, name in enumerate(components)}

    target = {}
    for instr, weights in target_weights.items():
        instr_weight = weights.get("weight", 0)
        direct_ratio = weights.get("direct", 0)
        early_ratio = weights.get("early", 0)
        target[component_index[f"{instr}_direct"]] = instr_weight * direct_ratio
        target[component_index[f"{instr}_early"]] = instr_weight * early_ratio

    signals = []
    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            i += 1
            continue

        # Nested signal format: "signal voc:" on its own line
        match = re.match(r"signal\s+(\S+):\s*$", stripped)
        if match:
            name = match.group(1)
            weights, i = parse_nested_signal(lines, i + 1, component_index)
            signals.append({"name": name, "weights": weights, "is_hall": False})
            continue

        # Inline signal format: "signal voc: 0.5 voc_direct, ..."
        match = re.match(r"signal\s+(\S+):\s*(.+)$", stripped)
        if match:
            name = match.group(1)
            weights = parse_signal_components(match.group(2), name, component_index)
            signals.append({"name": name, "weights": weights, "is_hall": False})
            i += 1
            continue

        i += 1

    return {
        "components": components,
        "component_index": component_index,
        "signals": signals,
        "target": target,
        "instruments": instruments,
        "hall_gain_db": hall_gain_db
    }, None


def add_hall_signals(spec, track_names):
    instruments = set(spec["instruments"])
    hall_gain_linear = db_to_linear(spec.get("hall_gain_db", 0))

    for track_name in track_names:
        track_name_normalized = track_name.lower().replace(" ", "_")

        for instr in instruments:
            if track_name_normalized == f"{instr}_hall":
                early_component = f"{instr}_early"
                if early_component in spec["component_index"]:
                    weights = {spec["component_index"][early_component]: hall_gain_linear}
                    spec["signals"].append({
                        "name": track_name,
                        "weights": weights,
                        "is_hall": True
                    })
                break


def build_matrices(spec):
    num_components = len(spec["components"])
    num_signals = len(spec["signals"])

    A = np.zeros((num_components, num_signals))
    is_hall = np.zeros(num_signals)
    signal_names = []

    for j, signal in enumerate(spec["signals"]):
        signal_names.append(signal["name"])
        is_hall[j] = 1 if signal["is_hall"] else 0
        for idx, weight in signal["weights"].items():
            A[idx, j] = weight

    target = np.zeros(num_components)
    for idx, weight in spec["target"].items():
        target[idx] = weight

    return A, target, is_hall, signal_names


def solve_mix(A, target, is_hall):
    """
    Solve for optimal fader levels.

    Minimizes: ||A @ x - target||^2 + hall_penalty * ||x * is_hall||^2
    Subject to: x >= 0

    This finds the closest achievable mix to the target while penalizing
    artificial reverb (hall) usage.
    """
    num_signals = A.shape[1]

    # Weight for hall penalty relative to target matching
    # Small value means prioritize matching target over minimizing hall
    HALL_PENALTY = 0.01

    def objective(x):
        residual = A @ x - target
        target_error = np.sum(residual ** 2)
        hall_penalty = HALL_PENALTY * np.sum((x * is_hall) ** 2)
        return target_error + hall_penalty

    def objective_grad(x):
        residual = A @ x - target
        target_grad = 2 * A.T @ residual
        hall_grad = 2 * HALL_PENALTY * x * is_hall
        return target_grad + hall_grad

    bounds = [(0, None) for _ in range(num_signals)]
    x0 = np.ones(num_signals) * 0.3

    result = minimize(
        objective,
        x0,
        method="L-BFGS-B",
        jac=objective_grad,
        bounds=bounds,
        options={"ftol": 1e-12, "maxiter": 1000}
    )

    residual = A @ result.x - target
    error = np.linalg.norm(residual)

    return result.x, error, result.success


def main():
    if len(sys.argv) != 4:
        print("Usage: python3 automix_solve.py <spec_file> <track_list_file> <output_file>", file=sys.stderr)
        sys.exit(1)

    spec_file = sys.argv[1]
    track_list_file = sys.argv[2]
    output_file = sys.argv[3]

    # Parse spec
    spec, err = parse_spec_file(spec_file)
    if not spec:
        result = {"success": False, "error": err}
        with open(output_file, "w") as f:
            json.dump(result, f)
        sys.exit(1)

    # Read track list
    with open(track_list_file, "r") as f:
        track_names = [line.strip() for line in f if line.strip()]

    # Add hall signals based on track names
    add_hall_signals(spec, track_names)

    # Build matrices and solve
    A, target, is_hall, signal_names = build_matrices(spec)

    # Log analysis info
    analysis_lines = []
    analysis_lines.append("Signal matrix (what each signal contributes to each component):")
    for j, sig_name in enumerate(signal_names):
        contributions = []
        for i, comp_name in enumerate(spec["components"]):
            if A[i, j] > 0.001:
                contributions.append(f"{comp_name}: {A[i,j]*100:.1f}%")
        hall_marker = " [hall]" if is_hall[j] else ""
        analysis_lines.append(f"  {sig_name}{hall_marker}: {', '.join(contributions)}")

    analysis_lines.append("")
    analysis_lines.append("Target mix:")
    for i, comp_name in enumerate(spec["components"]):
        analysis_lines.append(f"  {comp_name}: {target[i]*100:.1f}%")

    solution, error, success = solve_mix(A, target, is_hall)

    # Build result
    levels = {}
    for j, name in enumerate(signal_names):
        levels[name] = {
            "linear": float(solution[j]),
            "db": float(linear_to_db(solution[j])),
            "is_hall": bool(is_hall[j])
        }

    # Compute achieved mix
    achieved = A @ solution
    achieved_mix = {}
    for i, name in enumerate(spec["components"]):
        achieved_mix[name] = {
            "achieved": float(achieved[i]),
            "target": float(target[i]),
            "diff": float(achieved[i] - target[i])
        }

    # Generate helpful error message if target not achievable
    error_message = None
    if error > 0.01:
        # Find which components have the biggest discrepancy
        problems = []
        for name, data in achieved_mix.items():
            diff = data["diff"]
            if abs(diff) > 0.01:
                if diff > 0:
                    problems.append(f"{name}: getting {data['achieved']*100:.1f}% but target is {data['target']*100:.1f}% (too much baked into source signals)")
                else:
                    problems.append(f"{name}: getting {data['achieved']*100:.1f}% but target is {data['target']*100:.1f}% (not enough available)")
        if problems:
            error_message = "Target mix not achievable:\n" + "\n".join(problems)

    result = {
        "success": bool(success and error < 0.01),
        "error": float(error),
        "error_message": error_message,
        "analysis": "\n".join(analysis_lines),
        "levels": levels,
        "achieved_mix": achieved_mix,
        "instruments": spec["instruments"],
        "components": spec["components"]
    }

    with open(output_file, "w") as f:
        json.dump(result, f, indent=2)


if __name__ == "__main__":
    main()
