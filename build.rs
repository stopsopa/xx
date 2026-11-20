use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=XX_VERSION");

    // If XX_VERSION env var is explicitly provided, respect it (e.g. "dev" from compile.sh or tag from CI)
    if let Ok(val) = std::env::var("XX_VERSION") {
        let trimmed = val.trim();
        if !trimmed.is_empty() {
            println!("cargo:rustc-env=XX_BUILD_VERSION={trimmed}");
            return;
        }
    }

    // Try reading exact git tag
    let output = Command::new("git")
        .args(["describe", "--tags", "--exact-match"])
        .output();

    if let Ok(out) = output {
        if out.status.success() {
            let tag = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !tag.is_empty() {
                println!("cargo:rustc-env=XX_BUILD_VERSION={tag}");
                return;
            }
        }
    }

    // Local / un-tagged fallback
    println!("cargo:rustc-env=XX_BUILD_VERSION=dev");
}
