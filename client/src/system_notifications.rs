use std::env;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const MAX_TITLE_CHARS: usize = 120;
const MAX_MESSAGE_CHARS: usize = 512;

fn helper_name() -> &'static str {
    if cfg!(windows) {
        "PrismNotifier.exe"
    } else {
        "PrismNotifier"
    }
}

fn push_candidate(candidates: &mut Vec<PathBuf>, path: impl Into<PathBuf>) {
    let path = path.into();
    if !candidates.iter().any(|candidate| candidate == &path) {
        candidates.push(path);
    }
}

fn helper_candidates() -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    // Only load a helper installed next to the trusted PrismChat executable.
    // Environment variables and the current working directory are intentionally
    // ignored to prevent binary planting.
    if let Ok(executable) = env::current_exe() {
        if let Some(directory) = executable.parent() {
            push_candidate(&mut candidates, directory.join(helper_name()));
            if let Some(target_directory) = directory.parent() {
                push_candidate(
                    &mut candidates,
                    target_directory
                        .join("frontend-codex-build")
                        .join(helper_name()),
                );
            }
        }
    }
    candidates
}
fn find_helper() -> Result<PathBuf, String> {
    helper_candidates()
        .into_iter()
        .find(|candidate| candidate.is_file())
        .ok_or_else(|| format!("{} не найден; соберите frontend", helper_name()))
}

fn limited(value: &str, max_chars: usize) -> String {
    value.trim().chars().take(max_chars).collect()
}

pub fn show(title: &str, message: &str) -> Result<(), String> {
    let message = limited(message, MAX_MESSAGE_CHARS);
    if message.is_empty() {
        return Err("текст уведомления пуст".to_owned());
    }
    let title = limited(title, MAX_TITLE_CHARS);
    let notification_title = if title.is_empty() {
        "PrismChat"
    } else {
        title.as_str()
    };
    let helper = find_helper()?;
    let mut command = Command::new(&helper);
    command
        .arg("--title")
        .arg(notification_title)
        .arg("--message")
        .arg(message)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(windows)]
    command.creation_flags(0x0800_0000);

    command
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("не удалось запустить {}: {error}", helper.display()))
}

#[cfg(test)]
mod tests {
    use super::limited;

    #[test]
    fn notification_text_is_trimmed_and_bounded() {
        assert_eq!(limited("  hello  ", 10), "hello");
        assert_eq!(limited("abcdef", 3), "abc");
    }
}
