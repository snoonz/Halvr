use crate::events::{CompletionPayload, ErrorPayload, ProgressPayload};
use crate::models::{
    ConversionSettings, ErrorInfo, QueueItem, QueueItemStatus,
};
use crate::services::{
    ffmpeg::{find_ffmpeg, find_ffprobe},
    is_supported, read_metadata, resolve_output_path,
};
use crate::state::AppState;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, State};

#[tauri::command]
pub async fn start_conversion(
    app: AppHandle,
    state: State<'_, AppState>,
    paths: Vec<String>,
    settings: ConversionSettings,
) -> Result<Vec<QueueItem>, String> {
    let state_arc = state.0.clone();

    // Resolve ffmpeg/ffprobe paths
    {
        let mut inner = state_arc.lock().unwrap();
        if inner.ffmpeg_path.is_none() {
            inner.ffmpeg_path = find_ffmpeg();
        }
        if inner.ffprobe_path.is_none() {
            inner.ffprobe_path = find_ffprobe();
        }
        inner.settings = settings;
    }

    // Create queue items from paths
    let new_items: Vec<QueueItem> = paths
        .iter()
        .map(|path| {
            let filename = std::path::Path::new(path)
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();

            if is_supported(path) {
                QueueItem::new(path.clone(), filename)
            } else {
                let ext = std::path::Path::new(path)
                    .extension()
                    .map(|e| e.to_string_lossy().to_uppercase())
                    .unwrap_or_default();
                QueueItem {
                    id: uuid::Uuid::new_v4().to_string(),
                    input_path: path.clone(),
                    filename,
                    status: QueueItemStatus::Skipped {
                        error: ErrorInfo {
                            title: "Unsupported Format".to_string(),
                            message: format!("{ext} format is not supported."),
                        },
                    },
                }
            }
        })
        .collect();

    let should_start = {
        let mut inner = state_arc.lock().unwrap();
        inner.queue.extend(new_items.clone());
        let was_processing = inner.is_processing;
        if !was_processing {
            inner.is_processing = true;
            inner.is_cancelled = false;
        }
        !was_processing
    };

    if should_start {
        let app_handle = app.clone();
        let state_clone = state_arc.clone();
        tokio::spawn(async move {
            process_queue(app_handle, state_clone).await;
        });
    }

    let inner = state_arc.lock().unwrap();
    Ok(inner.queue.clone())
}

#[tauri::command]
pub fn add_to_queue(
    state: State<'_, AppState>,
    paths: Vec<String>,
) -> Vec<QueueItem> {
    let mut inner = state.0.lock().unwrap();

    for path in &paths {
        let filename = std::path::Path::new(path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();

        if is_supported(path) {
            inner.queue.push(QueueItem::new(path.clone(), filename));
        } else {
            let ext = std::path::Path::new(path)
                .extension()
                .map(|e| e.to_string_lossy().to_uppercase())
                .unwrap_or_default();
            inner.queue.push(QueueItem {
                id: uuid::Uuid::new_v4().to_string(),
                input_path: path.clone(),
                filename,
                status: QueueItemStatus::Skipped {
                    error: ErrorInfo {
                        title: "Unsupported Format".to_string(),
                        message: format!("{ext} format is not supported."),
                    },
                },
            });
        }
    }

    inner.queue.clone()
}

#[tauri::command]
pub fn cancel_conversion(state: State<'_, AppState>) {
    let mut inner = state.0.lock().unwrap();
    inner.is_cancelled = true;
    inner.converter.cancel();

    let cancel_error = ErrorInfo {
        title: "Cancel".to_string(),
        message: "Cancelled by user.".to_string(),
    };

    inner.queue = inner
        .queue
        .iter()
        .map(|item| match &item.status {
            QueueItemStatus::Pending | QueueItemStatus::Converting { .. } => QueueItem {
                status: QueueItemStatus::Skipped {
                    error: cancel_error.clone(),
                },
                ..item.clone()
            },
            _ => item.clone(),
        })
        .collect();
}

#[tauri::command]
pub fn remove_item(state: State<'_, AppState>, item_id: String) -> Vec<QueueItem> {
    let mut inner = state.0.lock().unwrap();
    inner.queue.retain(|item| item.id != item_id);
    inner.queue.clone()
}

#[tauri::command]
pub fn clear_completed(state: State<'_, AppState>) -> Vec<QueueItem> {
    let mut inner = state.0.lock().unwrap();
    inner.queue.retain(|item| {
        matches!(
            item.status,
            QueueItemStatus::Pending | QueueItemStatus::Converting { .. }
        )
    });
    inner.queue.clone()
}

#[tauri::command]
pub fn get_queue(state: State<'_, AppState>) -> Vec<QueueItem> {
    let inner = state.0.lock().unwrap();
    inner.queue.clone()
}

/// Claims the next pending item from the queue, marking it as Converting to
/// prevent other concurrent workers from picking it up.
fn claim_next_pending(
    state: &Arc<Mutex<crate::state::AppStateInner>>,
) -> Option<QueueItem> {
    let mut inner = state.lock().unwrap();
    if inner.is_cancelled {
        return None;
    }
    let idx = inner
        .queue
        .iter()
        .position(|i| matches!(i.status, QueueItemStatus::Pending))?;
    let item = inner.queue[idx].clone();
    inner.queue[idx].status = QueueItemStatus::Converting { progress: 0.0 };
    Some(item)
}

async fn process_queue(app: AppHandle, state: Arc<Mutex<crate::state::AppStateInner>>) {
    let (max_parallel, ffmpeg_path, ffprobe_path, settings) = {
        let inner = state.lock().unwrap();
        inner.converter.reset_cancel();
        (
            inner.max_parallel,
            inner.ffmpeg_path.clone(),
            inner.ffprobe_path.clone(),
            inner.settings.clone(),
        )
    };

    let mut join_set = tokio::task::JoinSet::new();

    loop {
        // Fill slots up to max_parallel with new pending items.
        while join_set.len() < max_parallel {
            match claim_next_pending(&state) {
                Some(item) => {
                    let app_clone = app.clone();
                    let state_clone = state.clone();
                    let ffmpeg = ffmpeg_path.clone();
                    let ffprobe = ffprobe_path.clone();
                    let s = settings.clone();
                    join_set.spawn(async move {
                        convert_item(app_clone, state_clone, item, ffmpeg, ffprobe, s).await;
                    });
                }
                None => break,
            }
        }

        if join_set.is_empty() {
            break;
        }

        // Wait for at least one conversion to finish before checking for more work.
        join_set.join_next().await;

        if state.lock().unwrap().is_cancelled {
            while join_set.join_next().await.is_some() {}
            break;
        }
    }

    let mut inner = state.lock().unwrap();
    inner.is_processing = false;
}

async fn convert_item(
    app: AppHandle,
    state: Arc<Mutex<crate::state::AppStateInner>>,
    item: QueueItem,
    ffmpeg_path: Option<String>,
    ffprobe_path: Option<String>,
    settings: ConversionSettings,
) {
    let item_id = item.id.clone();

    // Read metadata
    let ffprobe = match ffprobe_path {
        Some(p) => p,
        None => {
            update_item_status(
                &state,
                &item_id,
                QueueItemStatus::Skipped {
                    error: ErrorInfo {
                        title: "Error".to_string(),
                        message: "ffprobe not found".to_string(),
                    },
                },
            );
            let _ = app.emit(
                "conversion-error",
                ErrorPayload {
                    item_id: item_id.clone(),
                    title: "Error".to_string(),
                    message: "ffprobe not found".to_string(),
                },
            );
            return;
        }
    };

    let metadata = match read_metadata(&ffprobe, &item.input_path).await {
        Ok(m) => m,
        Err(e) => {
            let msg = e.to_string();
            update_item_status(
                &state,
                &item_id,
                QueueItemStatus::Skipped {
                    error: ErrorInfo {
                        title: "Load Failed".to_string(),
                        message: msg.clone(),
                    },
                },
            );
            let _ = app.emit(
                "conversion-error",
                ErrorPayload {
                    item_id: item_id.clone(),
                    title: "Load Failed".to_string(),
                    message: msg,
                },
            );
            return;
        }
    };

    // Check if already HEVC
    if metadata.is_already_hevc {
        update_item_status(
            &state,
            &item_id,
            QueueItemStatus::Skipped {
                error: ErrorInfo {
                    title: "Conversion Not Needed".to_string(),
                    message: "Already encoded in HEVC.".to_string(),
                },
            },
        );
        let _ = app.emit(
            "conversion-error",
            ErrorPayload {
                item_id: item_id.clone(),
                title: "Conversion Not Needed".to_string(),
                message: "Already encoded in HEVC.".to_string(),
            },
        );
        return;
    }

    // Resolve output path
    let output_path = resolve_output_path(&item.input_path, None);

    // Get ffmpeg path
    let ffmpeg = match ffmpeg_path {
        Some(p) => p,
        None => {
            update_item_status(
                &state,
                &item_id,
                QueueItemStatus::Skipped {
                    error: ErrorInfo {
                        title: "Error".to_string(),
                        message: "ffmpeg not found".to_string(),
                    },
                },
            );
            let _ = app.emit(
                "conversion-error",
                ErrorPayload {
                    item_id: item_id.clone(),
                    title: "Error".to_string(),
                    message: "ffmpeg not found".to_string(),
                },
            );
            return;
        }
    };

    // Run conversion
    let (progress_tx, mut progress_rx) = tokio::sync::mpsc::unbounded_channel::<f64>();

    let converter = {
        let inner = state.lock().unwrap();
        crate::services::FfmpegConverter::new_from(&inner.converter)
    };

    let app_clone = app.clone();
    let item_id_clone = item_id.clone();
    let state_clone = state.clone();

    // Spawn progress listener
    let progress_handle = tokio::spawn(async move {
        while let Some(progress) = progress_rx.recv().await {
            update_item_status(
                &state_clone,
                &item_id_clone,
                QueueItemStatus::Converting { progress },
            );
            let _ = app_clone.emit(
                "conversion-progress",
                ProgressPayload {
                    item_id: item_id_clone.clone(),
                    progress,
                },
            );
        }
    });

    let result = converter
        .convert(
            &ffmpeg,
            &item.input_path,
            &output_path,
            &settings,
            metadata.duration_secs,
            progress_tx,
        )
        .await;

    // Wait for progress listener to finish
    let _ = progress_handle.await;

    match result {
        Ok(out_path) => {
            // Preserve timestamps if enabled
            if settings.preserve_timestamp {
                copy_timestamps(&item.input_path, &out_path);
            }

            update_item_status(
                &state,
                &item_id,
                QueueItemStatus::Completed {
                    output_path: out_path.clone(),
                },
            );
            let _ = app.emit(
                "conversion-complete",
                CompletionPayload {
                    item_id: item_id.clone(),
                    output_path: out_path,
                },
            );
        }
        Err(e) => {
            let msg = e.to_string();
            update_item_status(
                &state,
                &item_id,
                QueueItemStatus::Skipped {
                    error: ErrorInfo {
                        title: "Conversion Failed".to_string(),
                        message: msg.clone(),
                    },
                },
            );
            let _ = app.emit(
                "conversion-error",
                ErrorPayload {
                    item_id: item_id.clone(),
                    title: "Conversion Failed".to_string(),
                    message: msg,
                },
            );
        }
    }
}

fn update_item_status(
    state: &Arc<Mutex<crate::state::AppStateInner>>,
    item_id: &str,
    status: QueueItemStatus,
) {
    let mut inner = state.lock().unwrap();
    if let Some(item) = inner.queue.iter_mut().find(|i| i.id == item_id) {
        item.status = status;
    }
}

fn copy_timestamps(source: &str, dest: &str) {
    let Ok(source_meta) = std::fs::metadata(source) else {
        return;
    };
    let Ok(modified) = source_meta.modified() else {
        return;
    };
    let _ = filetime::set_file_mtime(
        dest,
        filetime::FileTime::from_system_time(modified),
    );
}
