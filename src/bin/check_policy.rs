use std::env;
use std::io::{self, Read};
use std::process::ExitCode;

use anyhow::{Context, Result, anyhow};
use opa_wasm::{Runtime, read_bundle, wasmtime};
use serde_json::Value;

const DEFAULT_BUNDLE_PATH: &str = "build/wasm/github_mcp.tar.gz";
const DEFAULT_ENTRYPOINT: &str = "coding/github_mcp/allow";
const BLOCKED_MESSAGE: &str = "[POLICY BLOCKED] Aktion verstoesst gegen Compliance-Richtlinien.";
const BLOCKED_EXIT: u8 = 2;

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    match run().await {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => {
            eprintln!("{BLOCKED_MESSAGE}");
            ExitCode::from(BLOCKED_EXIT)
        }
        Err(error) => {
            eprintln!("[POLICY ERROR] {error:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<bool> {
    let mut args = env::args().skip(1);
    let bundle_path = args
        .next()
        .unwrap_or_else(|| DEFAULT_BUNDLE_PATH.to_string());
    let entrypoint = args
        .next()
        .unwrap_or_else(|| DEFAULT_ENTRYPOINT.to_string());

    let mut raw_input = String::new();
    io::stdin()
        .read_to_string(&mut raw_input)
        .context("failed to read policy input from stdin")?;

    if raw_input.trim().is_empty() {
        return Ok(true);
    }

    let input: Value =
        serde_json::from_str(&raw_input).context("failed to parse policy input JSON")?;
    let decision = evaluate_policy(&bundle_path, &entrypoint, &input).await?;

    Ok(is_allowed(&decision))
}

fn is_allowed(decision: &Value) -> bool {
    if decision == &Value::Bool(true) {
        return true;
    }

    decision
        .as_array()
        .and_then(|results| results.first())
        .and_then(|result| result.get("result"))
        == Some(&Value::Bool(true))
}

async fn evaluate_policy(bundle_path: &str, entrypoint: &str, input: &Value) -> Result<Value> {
    let engine = wasmtime::Engine::default();
    let module_bytes = read_bundle(bundle_path)
        .await
        .with_context(|| format!("failed to read OPA bundle at {bundle_path}"))?;
    let module = wasmtime::Module::new(&engine, module_bytes)
        .map_err(|error| anyhow!("failed to compile OPA WASM module: {error}"))?;
    let mut store = wasmtime::Store::new(&engine, ());

    let runtime = Runtime::new(&mut store, &module)
        .await
        .context("failed to instantiate OPA runtime")?;
    let policy = runtime
        .without_data(&mut store)
        .await
        .context("failed to initialize OPA policy data")?;

    policy
        .evaluate(&mut store, entrypoint, input)
        .await
        .with_context(|| format!("failed to evaluate OPA entrypoint {entrypoint}"))
}
