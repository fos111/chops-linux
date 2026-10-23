use std::net::{SocketAddr, TcpStream};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::time::Duration;

use tauri::Manager;

struct Sidecar {
    child: Mutex<Option<Child>>,
}

impl Sidecar {
    fn start() -> Self {
        let port = std::env::var("CHOPSD_PORT")
            .ok()
            .and_then(|value| value.parse::<u16>().ok())
            .unwrap_or(47115);
        if port_is_open(port) {
            return Self {
                child: Mutex::new(None),
            };
        }

        let Some(path) = sidecar_path() else {
            eprintln!("chopsd sidecar not found; the desktop shell will show an offline error");
            return Self {
                child: Mutex::new(None),
            };
        };

        let mut command = Command::new(&path);
        command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        unsafe {
            command.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }

        match command.spawn() {
            Ok(child) => Self {
                child: Mutex::new(Some(child)),
            },
            Err(error) => {
                eprintln!("failed to start chopsd at {}: {error}", path.display());
                Self {
                    child: Mutex::new(None),
                }
            }
        }
    }

    fn stop(&self) {
        if let Ok(mut guard) = self.child.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
    }
}

impl Drop for Sidecar {
    fn drop(&mut self) {
        self.stop();
    }
}

fn port_is_open(port: u16) -> bool {
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&address, Duration::from_millis(200)).is_ok()
}

fn sidecar_path() -> Option<PathBuf> {
    if let Ok(explicit) = std::env::var("CHOPSD_PATH") {
        let path = PathBuf::from(explicit);
        if path.is_file() {
            return Some(path);
        }
    }

    let exe = std::env::current_exe().ok()?;
    let exe_dir = exe.parent()?.to_path_buf();
    let mut candidates = vec![
        exe_dir.join("chopsd"),
        exe_dir.join("chopsd-x86_64-unknown-linux-gnu"),
    ];
    if let Some(manifest_dir) = option_env!("CARGO_MANIFEST_DIR") {
        candidates.push(
            PathBuf::from(manifest_dir).join("bin/chopsd-x86_64-unknown-linux-gnu"),
        );
    }
    candidates.push(PathBuf::from("bin/chopsd-x86_64-unknown-linux-gnu"));

    candidates.into_iter().find(|path| path.is_file())
}

#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {name}! You've been greeted from Rust!")
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![greet])
        .setup(|app| {
            app.manage(Sidecar::start());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    app.run(|app_handle, event| {
        if let tauri::RunEvent::Exit = event {
            if let Some(sidecar) = app_handle.try_state::<Sidecar>() {
                sidecar.stop();
            }
        }
    });
}
