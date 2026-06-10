use crate::models::{ConversionError, ConversionSettings};
use regex::Regex;
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::mpsc::UnboundedSender;

/// Wraps an ffmpeg child process, providing conversion and cancellation.
pub struct FfmpegConverter {
    current_child: Arc<Mutex<Option<Child>>>,
    /// Shared registry of all active child slots across sibling converters.
    child_registry: Arc<Mutex<Vec<Arc<Mutex<Option<Child>>>>>>,
    is_cancelled: Arc<Mutex<bool>>,
}

impl FfmpegConverter {
    pub fn new() -> Self {
        Self {
            current_child: Arc::new(Mutex::new(None)),
            child_registry: Arc::new(Mutex::new(Vec::new())),
            is_cancelled: Arc::new(Mutex::new(false)),
        }
    }

    /// Creates a new converter that shares cancel state and child registry with the original.
    pub fn new_from(other: &Self) -> Self {
        Self {
            current_child: Arc::new(Mutex::new(None)),
            child_registry: Arc::clone(&other.child_registry),
            is_cancelled: Arc::clone(&other.is_cancelled),
        }
    }

    /// Clears the cancelled flag so a fresh queue run can start.
    pub fn reset_cancel(&self) {
        *self.is_cancelled.lock().unwrap() = false;
    }

    /// Runs an ffmpeg conversion, reporting progress through `progress_sender`.
    ///
    /// Returns the output path on success.
    pub async fn convert(
        &self,
        ffmpeg_path: &str,
        input_path: &str,
        output_path: &str,
        settings: &ConversionSettings,
        duration_secs: f64,
        progress_sender: UnboundedSender<f64>,
    ) -> Result<String, ConversionError> {
        // Register this child slot so cancel() can reach it even before spawn.
        {
            let mut registry = self.child_registry.lock().unwrap();
            registry.push(Arc::clone(&self.current_child));
        }

        let result = self
            .run_convert(
                ffmpeg_path,
                input_path,
                output_path,
                settings,
                duration_secs,
                progress_sender,
            )
            .await;

        // Unregister regardless of outcome.
        {
            let mut registry = self.child_registry.lock().unwrap();
            registry.retain(|r| !Arc::ptr_eq(r, &self.current_child));
        }

        result
    }

    async fn run_convert(
        &self,
        ffmpeg_path: &str,
        input_path: &str,
        output_path: &str,
        settings: &ConversionSettings,
        duration_secs: f64,
        progress_sender: UnboundedSender<f64>,
    ) -> Result<String, ConversionError> {
        let args = build_args(input_path, output_path, settings);

        let mut child = Command::new(ffmpeg_path)
            .args(&args)
            .stderr(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stdin(std::process::Stdio::null())
            .spawn()
            .map_err(|e| ConversionError::ExportFailed(format!("Failed to spawn ffmpeg: {e}")))?;

        // Store the child handle so `cancel()` can reach it.
        let stderr = child.stderr.take();
        {
            let mut current = self.current_child.lock().unwrap();
            *current = Some(child);
        }

        // Parse progress from stderr
        if let Some(stderr_stream) = stderr {
            self.read_progress(stderr_stream, duration_secs, &progress_sender)
                .await;
        }

        // Take the child out of the mutex so we can await without holding the lock
        let mut child = {
            let mut current = self.current_child.lock().unwrap();
            match current.take() {
                Some(c) => c,
                None => return Err(ConversionError::Cancelled),
            }
        };

        // Wait for the process to finish
        let status = child.wait().await;

        // Check cancellation
        if *self.is_cancelled.lock().unwrap() {
            cleanup_partial_file(output_path);
            return Err(ConversionError::Cancelled);
        }

        match status {
            Ok(exit) if exit.success() => {
                let _ = progress_sender.send(1.0);
                Ok(output_path.to_string())
            }
            Ok(exit) => {
                cleanup_partial_file(output_path);
                Err(ConversionError::ExportFailed(format!(
                    "ffmpeg exited with code {}",
                    exit.code().unwrap_or(-1)
                )))
            }
            Err(e) => {
                cleanup_partial_file(output_path);
                Err(ConversionError::ExportFailed(format!(
                    "Failed to wait on ffmpeg process: {e}"
                )))
            }
        }
    }

    /// Signals all running ffmpeg processes to stop and marks the conversion as cancelled.
    pub fn cancel(&self) {
        *self.is_cancelled.lock().unwrap() = true;

        let registry = self.child_registry.lock().unwrap();
        for child_slot in registry.iter() {
            let mut child = child_slot.lock().unwrap();
            if let Some(ref mut c) = *child {
                let _ = c.start_kill();
            }
        }
    }

    /// Reads stderr byte-by-byte, parsing ffmpeg's `time=` progress marker.
    ///
    /// ffmpeg writes progress updates separated by `\r` (carriage return),
    /// only emitting `\n` at the end or on status changes. We must split on
    /// both `\r` and `\n` to receive updates in real time.
    async fn read_progress(
        &self,
        stderr: tokio::process::ChildStderr,
        duration_secs: f64,
        progress_sender: &UnboundedSender<f64>,
    ) {
        let mut reader = BufReader::new(stderr);
        let time_re = Regex::new(r"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})").unwrap();
        let mut buf = Vec::with_capacity(512);

        loop {
            let byte = match reader.read_u8().await {
                Ok(b) => b,
                Err(_) => break,
            };

            if byte == b'\r' || byte == b'\n' {
                if !buf.is_empty() {
                    if let Ok(segment) = std::str::from_utf8(&buf) {
                        if let Some(caps) = time_re.captures(segment) {
                            let current_secs = parse_time_captures(&caps);
                            if duration_secs > 0.0 {
                                let progress = (current_secs / duration_secs).min(0.99);
                                let _ = progress_sender.send(progress);
                            }
                        }
                    }
                    buf.clear();
                }
            } else {
                buf.push(byte);
            }

            if *self.is_cancelled.lock().unwrap() {
                break;
            }
        }
    }
}

/// Builds the ffmpeg argument list from conversion settings.
fn build_args(input_path: &str, output_path: &str, settings: &ConversionSettings) -> Vec<String> {
    let codec = settings.encoder.ffmpeg_codec();
    let quality_args = settings.preset.quality_args(&settings.encoder);

    let mut args = vec![
        "-nostdin".to_string(),
        "-i".to_string(),
        input_path.to_string(),
        "-c:v".to_string(),
        codec.to_string(),
    ];

    args.extend(quality_args);

    args.extend([
        "-c:a".to_string(),
        "copy".to_string(),
        "-tag:v".to_string(),
        "hvc1".to_string(),
        "-y".to_string(),
        output_path.to_string(),
    ]);

    args
}

/// Parses hour:minute:second.centisecond captures into total seconds.
fn parse_time_captures(caps: &regex::Captures) -> f64 {
    let hours: f64 = caps[1].parse().unwrap_or(0.0);
    let minutes: f64 = caps[2].parse().unwrap_or(0.0);
    let seconds: f64 = caps[3].parse().unwrap_or(0.0);
    let centis: f64 = caps[4].parse().unwrap_or(0.0);

    hours * 3600.0 + minutes * 60.0 + seconds + centis / 100.0
}

/// Removes a partial output file, ignoring errors.
fn cleanup_partial_file(path: &str) {
    let _ = std::fs::remove_file(path);
}

// ---------------------------------------------------------------------------
// FFmpeg / FFprobe path discovery
// ---------------------------------------------------------------------------

/// Searches for the ffmpeg binary in well-known locations and PATH.
pub fn find_ffmpeg() -> Option<String> {
    find_binary("ffmpeg")
}

/// Searches for the ffprobe binary in well-known locations and PATH.
pub fn find_ffprobe() -> Option<String> {
    find_binary("ffprobe")
}

fn find_binary(name: &str) -> Option<String> {
    // Platform-specific well-known paths
    let candidates: &[&str] = if cfg!(target_os = "macos") {
        &[
            &format!("/opt/homebrew/bin/{name}"),
            &format!("/usr/local/bin/{name}"),
        ]
    } else {
        &[]
    };

    for path in candidates {
        if std::path::Path::new(path).is_file() {
            return Some(path.to_string());
        }
    }

    // Fallback: search PATH via the `which` crate
    which::which(name)
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
}
