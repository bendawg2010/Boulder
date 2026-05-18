// Windows blocker — polls the foreground window for blocked-app
// matches while a focus session is active, surfaces a 3-second
// warning to the frontend, and terminates the offending process if
// the user doesn't bail out in time.
//
// Mirrors the Mac FocusBlocker semantics. Frontend pushes state in
// via the Tauri commands declared in main.rs:
//   • set_blocked_apps(paths)   — replace the blocked-app list
//   • set_focus_state(focusing) — turn the poller on/off
//   • cancel_block()            — user clicked "I'm back" within 3s

use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, Manager};

#[cfg(windows)]
use windows::Win32::{
    Foundation::{CloseHandle, HWND, BOOL, HANDLE},
    System::ProcessStatus::GetModuleFileNameExW,
    System::Threading::{
        OpenProcess, TerminateProcess, PROCESS_QUERY_LIMITED_INFORMATION,
        PROCESS_TERMINATE, PROCESS_VM_READ,
    },
    UI::WindowsAndMessaging::{
        GetForegroundWindow, GetWindowThreadProcessId, ShowWindow, SW_HIDE,
    },
};

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct BlockedApp {
    pub name: String,    // display name
    pub path: String,    // full exe path, lowercase
}

#[derive(Default)]
pub struct BlockerState {
    pub blocked_apps: Vec<BlockedApp>,
    pub focusing: bool,
    pub pending: Option<PendingBlock>,
}

#[derive(Clone)]
pub struct PendingBlock {
    pub pid: u32,
    pub app_name: String,
    pub started_at: Instant,
}

pub type SharedBlocker = Arc<Mutex<BlockerState>>;

#[derive(Clone, Serialize)]
pub struct WarnPayload {
    pub app_name: String,
    pub seconds: u32,
}

#[derive(Clone, Serialize)]
pub struct TerminatedPayload {
    pub app_name: String,
}

/// Spawn the polling loop in a Tokio task. Polls every 500ms.
pub fn spawn_poller(app_handle: AppHandle) {
    let shared = app_handle.state::<SharedBlocker>().inner().clone();
    tauri::async_runtime::spawn(async move {
        loop {
            tokio::time::sleep(Duration::from_millis(500)).await;
            poll_tick(&app_handle, &shared);
        }
    });
}

fn poll_tick(app_handle: &AppHandle, shared: &SharedBlocker) {
    let mut state = match shared.lock() {
        Ok(s) => s,
        Err(_) => return,
    };
    if !state.focusing || state.blocked_apps.is_empty() {
        // Clear any pending block — we're not focusing anymore.
        if state.pending.is_some() {
            state.pending = None;
        }
        return;
    }

    let (pid, exe_path) = match foreground_exe() {
        Some(v) => v,
        None => return,
    };
    let exe_lower = exe_path.to_lowercase();

    let matched = state.blocked_apps.iter()
        .find(|b| {
            let p = b.path.to_lowercase();
            exe_lower == p || exe_lower.ends_with(&format!("\\{}", &p.split('\\').last().unwrap_or("")))
        })
        .cloned();

    let matched = match matched {
        Some(m) => m,
        None => {
            // Foreground is not blocked — clear any in-flight block.
            if state.pending.is_some() {
                state.pending = None;
            }
            return;
        }
    };

    match &state.pending {
        Some(existing) if existing.pid == pid => {
            // Already counting down for this app. Check if expired.
            let elapsed = existing.started_at.elapsed();
            if elapsed >= Duration::from_secs(3) {
                let app_name = existing.app_name.clone();
                state.pending = None;
                // Drop the lock before terminating + emitting.
                drop(state);
                hide_and_terminate(pid);
                let _ = app_handle.emit("blocker:terminated", TerminatedPayload { app_name });
                return;
            }
            // else still counting down — nothing new to do
        }
        _ => {
            // New block — start the countdown + warn the frontend.
            hide_pid_windows(pid);
            state.pending = Some(PendingBlock {
                pid,
                app_name: matched.name.clone(),
                started_at: Instant::now(),
            });
            let payload = WarnPayload { app_name: matched.name, seconds: 3 };
            drop(state);
            let _ = app_handle.emit("blocker:warn", payload);
        }
    }
}

/// Frontend posts this after the user clicks "I'm back".
pub fn cancel(shared: &SharedBlocker) {
    if let Ok(mut s) = shared.lock() {
        s.pending = None;
    }
}

#[cfg(not(windows))]
fn foreground_exe() -> Option<(u32, String)> { None }

#[cfg(windows)]
fn foreground_exe() -> Option<(u32, String)> {
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.is_invalid() { return None; }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 { return None; }
        let handle = OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
            false,
            pid,
        ).ok()?;
        let mut buf: [u16; 1024] = [0; 1024];
        let len = GetModuleFileNameExW(handle, None, &mut buf);
        let _ = CloseHandle(handle);
        if len == 0 { return None; }
        let path = String::from_utf16_lossy(&buf[..len as usize]);
        Some((pid, path))
    }
}

#[cfg(not(windows))]
fn hide_pid_windows(_pid: u32) {}

#[cfg(windows)]
fn hide_pid_windows(_pid: u32) {
    // ShowWindow(SW_HIDE) on the foreground window — best-effort.
    unsafe {
        let hwnd = GetForegroundWindow();
        if !hwnd.is_invalid() {
            let _ = ShowWindow(hwnd, SW_HIDE);
        }
    }
}

#[cfg(not(windows))]
fn hide_and_terminate(_pid: u32) {}

#[cfg(windows)]
fn hide_and_terminate(pid: u32) {
    unsafe {
        // Hide first (cosmetic — user sees it disappear).
        let hwnd = GetForegroundWindow();
        if !hwnd.is_invalid() {
            let _ = ShowWindow(hwnd, SW_HIDE);
        }
        // Then SIGKILL-equivalent. No graceful path — Windows
        // TerminateProcess is the only knob.
        if let Ok(handle) = OpenProcess(PROCESS_TERMINATE, false, pid) {
            let _ = TerminateProcess(handle, 1);
            let _ = CloseHandle(handle);
        }
    }
}
