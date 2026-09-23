import { loadPolicy } from "@open-policy-agent/opa-wasm";
import fs from "fs";

async function main() {
  // 1. WASM-Datei laden
  const wasmBuffer = fs.readFileSync("../build/policy.wasm");
  const policy = await loadPolicy(wasmBuffer);

  // 2. Event-Payload von Claude Code über stdin einlesen
  const rawInput = fs.readFileSync(0, "utf-8");
  if (!rawInput.trim()) process.exit(0);
  
  const inputData = JSON.parse(rawInput);

  // 3. Rego Policy auswerten
  const results = policy.evaluate(inputData);
  const decision = results[0]?.result;

  // 4. Entscheidung prüfen
  // Falls die Policy fehlschlägt oder allow == false ist:
  if (!decision || decision.allow !== true) {
    const reason = decision?.reason || "Aktion verstößt gegen Compliance-Richtlinien.";
    
    // Fehlerursache an stderr ausgeben (Claude liest dies als Feedback)
    console.error(`[POLICY BLOCKED] ${reason}`);
    
    // Exit Code 2 signalisiert Claude Code, dass die Aktion abgelehnt wurde
    process.exit(2);
  }

  // Exit Code 0 erlaubt die Ausführung
  process.exit(0);
}

main().catch((err) => {
  console.error(`Skriptfehler: ${err.message}`);
  process.exit(2);
});
