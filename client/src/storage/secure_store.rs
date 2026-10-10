use rand::{rngs::OsRng, RngCore};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
};
use zeroize::{Zeroize, Zeroizing};

const MAGIC: &[u8] = b"PRISMSEC1\0";

#[cfg(windows)]
fn protect_for_current_user(data: &[u8]) -> Result<Vec<u8>, String> {
    use std::ptr;
    use windows_sys::Win32::{
        Foundation::{GetLastError, LocalFree},
        Security::Cryptography::{CryptProtectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB},
    };

    let input = CRYPT_INTEGER_BLOB {
        cbData: u32::try_from(data.len()).map_err(|_| "Секрет слишком велик".to_owned())?,
        pbData: data.as_ptr() as *mut u8,
    };
    let mut output = CRYPT_INTEGER_BLOB::default();
    if unsafe {
        CryptProtectData(
            &input,
            ptr::null(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        )
    } == 0
    {
        return Err(format!(
            "Windows DPAPI не смог защитить данные: error {}",
            unsafe { GetLastError() }
        ));
    }

    let encrypted =
        unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec() };
    unsafe {
        LocalFree(output.pbData.cast());
    }
    Ok(encrypted)
}

#[cfg(windows)]
fn unprotect_for_current_user(data: &[u8]) -> Result<Vec<u8>, String> {
    use std::ptr;
    use windows_sys::Win32::{
        Foundation::{GetLastError, LocalFree},
        Security::Cryptography::{
            CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
        },
    };

    let input = CRYPT_INTEGER_BLOB {
        cbData: u32::try_from(data.len()).map_err(|_| "Секрет слишком велик".to_owned())?,
        pbData: data.as_ptr() as *mut u8,
    };
    let mut output = CRYPT_INTEGER_BLOB::default();
    if unsafe {
        CryptUnprotectData(
            &input,
            ptr::null_mut(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
            CRYPTPROTECT_UI_FORBIDDEN,
            &mut output,
        )
    } == 0
    {
        return Err(format!(
            "Windows DPAPI не смог расшифровать данные: error {}",
            unsafe { GetLastError() }
        ));
    }

    let plain =
        unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize).to_vec() };
    unsafe {
        std::ptr::write_bytes(output.pbData, 0, output.cbData as usize);
        LocalFree(output.pbData.cast());
    }
    Ok(plain)
}

#[cfg(not(windows))]
fn protect_for_current_user(data: &[u8]) -> Result<Vec<u8>, String> {
    Ok(data.to_vec())
}

#[cfg(not(windows))]
fn unprotect_for_current_user(data: &[u8]) -> Result<Vec<u8>, String> {
    Ok(data.to_vec())
}

#[cfg(windows)]
fn replace_file(source: &Path, destination: &Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::{
        Foundation::GetLastError,
        Storage::FileSystem::{MoveFileExW, MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH},
    };
    let source = source
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    let destination = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect::<Vec<_>>();
    if unsafe {
        MoveFileExW(
            source.as_ptr(),
            destination.as_ptr(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
        )
    } == 0
    {
        return Err(format!(
            "Не удалось атомарно заменить защищённый файл: error {}",
            unsafe { GetLastError() }
        ));
    }
    Ok(())
}

#[cfg(not(windows))]
fn replace_file(source: &Path, destination: &Path) -> Result<(), String> {
    fs::rename(source, destination)
        .map_err(|error| format!("Не удалось атомарно заменить защищённый файл: {error}"))
}

pub fn harden_directory(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path)
        .map_err(|error| format!("Не удалось создать приватную папку: {error}"))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .map_err(|error| format!("Не удалось ограничить права папки: {error}"))?;
    }
    Ok(())
}

pub fn write_private_atomic(path: &Path, data: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "У защищённого файла нет родительской папки".to_owned())?;
    harden_directory(parent)?;

    let mut random = [0u8; 8];
    OsRng.fill_bytes(&mut random);
    let suffix = random
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    let filename = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("secret");
    let temporary = parent.join(format!(".{filename}.{suffix}.tmp"));

    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let result = (|| {
        let mut file = options
            .open(&temporary)
            .map_err(|error| format!("Не удалось создать временный защищённый файл: {error}"))?;
        file.write_all(data)
            .map_err(|error| format!("Не удалось записать защищённый файл: {error}"))?;
        file.sync_all()
            .map_err(|error| format!("Не удалось синхронизировать защищённый файл: {error}"))?;
        drop(file);
        replace_file(&temporary, path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

pub fn is_protected(data: &[u8]) -> bool {
    data.starts_with(MAGIC)
}

pub fn read_protected(path: &Path) -> Result<Vec<u8>, String> {
    let bytes =
        fs::read(path).map_err(|error| format!("Не удалось прочитать защищённый файл: {error}"))?;
    if !is_protected(&bytes) {
        return Ok(bytes);
    }
    unprotect_for_current_user(&bytes[MAGIC.len()..])
}

pub fn write_protected(path: &Path, plain: &[u8]) -> Result<(), String> {
    let mut encrypted = protect_for_current_user(plain)?;
    let mut payload = Vec::with_capacity(MAGIC.len() + encrypted.len());
    payload.extend_from_slice(MAGIC);
    payload.extend_from_slice(&encrypted);
    encrypted.zeroize();
    let result = write_private_atomic(path, &payload);
    payload.zeroize();
    result
}

pub fn load_or_create_store_passphrase(path: &Path) -> Result<Zeroizing<String>, String> {
    if path.exists() {
        let mut bytes = read_protected(path)?;
        let value = String::from_utf8(bytes.clone())
            .map_err(|_| "Файл ключа Matrix store повреждён".to_owned())?;
        bytes.zeroize();
        return Ok(Zeroizing::new(value));
    }

    let mut random = [0u8; 32];
    OsRng.fill_bytes(&mut random);
    let value = random
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>();
    random.zeroize();
    write_protected(path, value.as_bytes())?;
    Ok(Zeroizing::new(value))
}
