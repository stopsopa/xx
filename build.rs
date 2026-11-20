fn main() {
    println!("cargo:rerun-if-env-changed=XX_VERSION");

    // Version comes only from XX_VERSION (release workflow sets it to the pushed tag).
    // Everything else is "dev", the same value xx.sh in the repository carries:
    // the wrapper refuses to work with a binary of different version.
    let version = match std::env::var("XX_VERSION") {
        Ok(val) if !val.trim().is_empty() => val.trim().to_string(),
        _ => "dev".to_string(),
    };

    println!("cargo:rustc-env=XX_BUILD_VERSION={version}");
}
