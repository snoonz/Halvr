use crate::models::{ConversionSettings, EncoderInfo, QueueItem};
use crate::services::FfmpegConverter;
use std::sync::{Arc, Mutex};

pub struct AppStateInner {
    pub queue: Vec<QueueItem>,
    pub is_processing: bool,
    pub is_cancelled: bool,
    pub available_encoders: Vec<EncoderInfo>,
    pub settings: ConversionSettings,
    pub ffmpeg_path: Option<String>,
    pub ffprobe_path: Option<String>,
    pub converter: FfmpegConverter,
    /// Maximum number of files to encode simultaneously.
    /// Set to 2 on machines with more than 16 logical CPU cores, otherwise 1.
    pub max_parallel: usize,
}

impl AppStateInner {
    fn new() -> Self {
        let cores = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(1);
        let max_parallel = if cores > 16 { 2 } else { 1 };

        Self {
            queue: Vec::new(),
            is_processing: false,
            is_cancelled: false,
            available_encoders: Vec::new(),
            settings: ConversionSettings::default(),
            ffmpeg_path: None,
            ffprobe_path: None,
            converter: FfmpegConverter::new(),
            max_parallel,
        }
    }
}

pub struct AppState(pub Arc<Mutex<AppStateInner>>);

impl AppState {
    pub fn new() -> Self {
        Self(Arc::new(Mutex::new(AppStateInner::new())))
    }
}
