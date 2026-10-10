use std::{
    path::{Path, PathBuf},
    sync::LazyLock,
    time::Duration,
};
use tokio::sync::Semaphore;

const OPUS_SAMPLE_RATE: u32 = 48_000;
const OPUS_BITRATE: u32 = 24_000;
const MAX_WAV_BYTES: u64 = 32 * 1024 * 1024;
const MAX_VOICE_SECONDS: u64 = 5 * 60;
static TRANSCODE_SEMAPHORE: LazyLock<Semaphore> = LazyLock::new(|| Semaphore::new(1));

pub async fn transcode_wav_to_ogg_opus(input_path: &str) -> Result<PathBuf, String> {
    let _permit = tokio::time::timeout(Duration::from_secs(5), TRANSCODE_SEMAPHORE.acquire())
        .await
        .map_err(|_| "Кодировщик голосовых занят".to_owned())?
        .map_err(|_| "Кодировщик голосовых остановлен".to_owned())?;
    let input_path = PathBuf::from(input_path);
    tokio::time::timeout(
        Duration::from_secs(120),
        tokio::task::spawn_blocking(move || transcode_wav(&input_path)),
    )
    .await
    .map_err(|_| "Кодирование голосового превысило лимит времени".to_owned())?
    .map_err(|error| format!("Ошибка задачи кодирования голосового: {error}"))?
}

fn transcode_wav(input_path: &Path) -> Result<PathBuf, String> {
    let metadata = std::fs::symlink_metadata(input_path)
        .map_err(|error| format!("Не удалось проверить запись WAV: {error}"))?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err("Запись должна быть обычным WAV-файлом".to_owned());
    }
    if metadata.len() > MAX_WAV_BYTES {
        return Err("Запись WAV превышает лимит 32 МиБ".to_owned());
    }

    let mut reader = hound::WavReader::open(input_path)
        .map_err(|error| format!("Не удалось открыть запись WAV: {error}"))?;
    let spec = reader.spec();
    if !(1..=2).contains(&spec.channels) || !(8_000..=192_000).contains(&spec.sample_rate) {
        return Err("Неподдерживаемые каналы или частота WAV".to_owned());
    }
    let max_frames = u64::from(spec.sample_rate).saturating_mul(MAX_VOICE_SECONDS);
    if u64::from(reader.duration()) > max_frames {
        return Err("Голосовое сообщение длиннее 5 минут".to_owned());
    }
    let max_samples = usize::try_from(max_frames.saturating_mul(u64::from(spec.channels)))
        .map_err(|_| "Запись WAV слишком велика".to_owned())?;

    let interleaved = match spec.sample_format {
        hound::SampleFormat::Float => reader
            .samples::<f32>()
            .take(max_samples.saturating_add(1))
            .map(|sample| {
                sample
                    .map(sanitize_sample)
                    .map_err(|error| format!("Не удалось прочитать WAV: {error}"))
            })
            .collect::<Result<Vec<_>, _>>()?,
        hound::SampleFormat::Int => {
            if spec.bits_per_sample == 0 || spec.bits_per_sample > 32 {
                return Err(format!(
                    "Неподдерживаемая разрядность WAV: {} бит",
                    spec.bits_per_sample
                ));
            }
            let peak = ((1_u64 << (spec.bits_per_sample - 1)) - 1) as f32;
            reader
                .samples::<i32>()
                .take(max_samples.saturating_add(1))
                .map(|sample| {
                    sample
                        .map(|value| sanitize_sample(value as f32 / peak))
                        .map_err(|error| format!("Не удалось прочитать WAV: {error}"))
                })
                .collect::<Result<Vec<_>, _>>()?
        }
    };
    if interleaved.len() > max_samples {
        return Err("Голосовое сообщение превышает допустимую длительность".to_owned());
    }

    let channels = usize::from(spec.channels);
    if interleaved.is_empty() || interleaved.len() % channels != 0 {
        return Err("Запись с микрофона пуста или повреждена".to_owned());
    }

    let mono = interleaved
        .chunks_exact(channels)
        .map(|frame| frame.iter().copied().sum::<f32>() / channels as f32)
        .collect::<Vec<_>>();
    let pcm_48khz = resample_linear(&mono, spec.sample_rate, OPUS_SAMPLE_RATE);
    if pcm_48khz.is_empty() {
        return Err("Запись с микрофона пуста".to_owned());
    }

    let ogg_opus = ruopus::encode_ogg_opus(&pcm_48khz, 1, OPUS_BITRATE);
    if !ogg_opus.starts_with(b"OggS")
        || !ogg_opus
            .windows(b"OpusHead".len())
            .any(|part| part == b"OpusHead")
    {
        return Err("Кодер не создал корректный Ogg/Opus".to_owned());
    }

    let output_path = std::env::temp_dir().join(format!(
        "prismchat-voice-{}.ogg",
        uuid::Uuid::new_v4().simple()
    ));
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    let mut output = options
        .open(&output_path)
        .map_err(|error| format!("Не удалось создать Ogg/Opus: {error}"))?;
    std::io::Write::write_all(&mut output, &ogg_opus)
        .map_err(|error| format!("Не удалось сохранить Ogg/Opus: {error}"))?;
    Ok(output_path)
}

fn sanitize_sample(sample: f32) -> f32 {
    if sample.is_finite() {
        sample.clamp(-1.0, 1.0)
    } else {
        0.0
    }
}

fn resample_linear(input: &[f32], input_rate: u32, output_rate: u32) -> Vec<f32> {
    if input.is_empty() || input_rate == 0 || output_rate == 0 {
        return Vec::new();
    }
    if input_rate == output_rate {
        return input.to_vec();
    }
    let output_len = ((input.len() as u64 * u64::from(output_rate) + u64::from(input_rate) / 2)
        / u64::from(input_rate)) as usize;
    let rate_ratio = input_rate as f64 / output_rate as f64;
    (0..output_len)
        .map(|index| {
            let position = index as f64 * rate_ratio;
            let left = (position.floor() as usize).min(input.len() - 1);
            let right = (left + 1).min(input.len() - 1);
            let fraction = (position - left as f64) as f32;
            input[left] + (input[right] - input[left]) * fraction
        })
        .collect()
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn creates_decodable_ogg_opus_from_stereo_wav() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let input_path = std::env::temp_dir().join(format!(
            "prismchat-voice-test-{}-{unique}.wav",
            std::process::id()
        ));
        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: 44_100,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(&input_path, spec).unwrap();
        for index in 0..44_100 {
            let sample = (0.25
                * (2.0 * std::f32::consts::PI * 440.0 * index as f32 / 44_100.0).sin()
                * i16::MAX as f32) as i16;
            writer.write_sample(sample).unwrap();
            writer.write_sample(sample).unwrap();
        }
        writer.finalize().unwrap();

        let output_path = transcode_wav(&input_path).unwrap();
        let encoded = std::fs::read(&output_path).unwrap();
        assert!(encoded.starts_with(b"OggS"));
        assert!(encoded.windows(8).any(|part| part == b"OpusHead"));
        let (decoded, header) = ruopus::decode_ogg_opus(&encoded).unwrap();
        assert_eq!(header.channel_count, 1);
        assert!(decoded.len() >= 47_000 && decoded.len() <= 49_000);

        let _ = std::fs::remove_file(input_path);
        let _ = std::fs::remove_file(output_path);
    }
}
