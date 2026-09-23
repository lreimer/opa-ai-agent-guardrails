import sys
import json

from opapywasm import OpaWasmPolicy


def main():
    # 1. WASM-Modul über Wasmtime laden
    policy = OpaWasmPolicy.from_wasm_file("../build/policy.wasm")

    # 2. Payload von Claude Code via stdin lesen
    raw_input = sys.stdin.read()
    if not raw_input.strip():
        sys.exit(0)

    input_data = json.loads(raw_input)

    # 3. Policy via Wasmtime auswerten
    decision = policy.evaluate(input_data)

    # 4. Zugriffsentscheidung auswerten
    if not isinstance(decision, dict) or decision.get("allow") is not True:
        sys.stderr.write("[POLICY BLOCKED] Aktion verstößt gegen Compliance-Richtlinien.\n")
        # Exit-Code 2 signalisiert Claude Code das Abbrechen des Werkzeugaufrufs
        sys.exit(2)

    # Exit-Code 0 erlaubt die Ausführung
    sys.exit(0)

if __name__ == "__main__":
    main()
