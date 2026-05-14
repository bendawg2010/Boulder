// Boulder for Windows — Tauri shell.
//
// Tray-first app. The main window stays hidden on launch; clicking
// the tray icon toggles it. Closing the window via the X just hides
// it, matching the Mac menubar-popover behavior. Quit is from the
// tray menu only.
//
// Mirror of the macOS AppDelegate.swift structure: tray + window +
// persistence-on-disk. Cloud sync lands when the v1.8 backend is up.

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, WindowEvent,
};

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::Builder::new().build())
        .setup(|app| {
            let show = MenuItem::with_id(app, "show", "Show Boulder", true, None::<&str>)?;
            let settings = MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit Boulder", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &settings, &quit])?;

            let _tray = TrayIconBuilder::with_id("boulder-tray")
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(false)
                .tooltip("Boulder")
                .menu(&menu)
                .menu_on_left_click(false)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "show" => toggle_main_window(app),
                    "settings" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                        // Typed event — the TS frontend listens via
                        // `listen('boulder://show-settings', ...)`. No
                        // arbitrary code execution; payload is unit.
                        let _ = app.emit("boulder://show-settings", ());
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
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the window hides it instead of quitting — matches
            // macOS menubar-popover behavior. Quit is tray-menu-only.
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
