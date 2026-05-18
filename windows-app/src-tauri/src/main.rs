// Boulder for Windows — Tauri shell hosting the same web-app frontend
// served at boulder-43p.pages.dev/app/. Adds a Windows-specific
// blocker (active-window monitor + TerminateProcess) since the web
// has no way to block apps from inside the browser.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod blocker;

use std::sync::{Arc, Mutex};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, WindowEvent,
};

use blocker::{BlockedApp, BlockerState, SharedBlocker};

// MARK: Tauri commands the frontend calls.

#[tauri::command]
fn set_blocked_apps(state: tauri::State<SharedBlocker>, apps: Vec<BlockedApp>) {
    if let Ok(mut s) = state.lock() {
        s.blocked_apps = apps;
    }
}

#[tauri::command]
fn set_focus_state(state: tauri::State<SharedBlocker>, focusing: bool) {
    if let Ok(mut s) = state.lock() {
        s.focusing = focusing;
        if !focusing { s.pending = None; }
    }
}

#[tauri::command]
fn cancel_block(state: tauri::State<SharedBlocker>) {
    blocker::cancel(&state);
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::Builder::new().build())
        .manage::<SharedBlocker>(Arc::new(Mutex::new(BlockerState::default())))
        .invoke_handler(tauri::generate_handler![
            set_blocked_apps,
            set_focus_state,
            cancel_block,
        ])
        .setup(|app| {
            // Tray + menu.
            let show = MenuItem::with_id(app, "show", "Show Boulder", true, None::<&str>)?;
            let community = MenuItem::with_id(app, "community", "Community Rock…", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Boulder", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &community, &quit])?;

            let _tray = TrayIconBuilder::with_id("boulder-tray")
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(false)
                .tooltip("Boulder — pet rock for your focus")
                .menu(&menu)
                .menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => toggle_main_window(app),
                    "community" => {
                        let _ = app.emit("boulder://open-community", ());
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        toggle_main_window(tray.app_handle());
                    }
                })
                .build(app)?;

            // Kick off the blocker poll loop.
            blocker::spawn_poller(app.handle().clone());

            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running boulder");
}

fn toggle_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        if window.is_visible().unwrap_or(false) {
            let _ = window.hide();
        } else {
            let _ = window.show();
            let _ = window.set_focus();
        }
    }
}
