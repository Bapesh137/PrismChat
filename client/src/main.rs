mod matrix;
mod network;
mod protocol;
mod storage;
mod system_notifications;

fn main() {
    println!("--- PrismChat Бэкенд запущен ---");

    let runtime_workers = std::thread::available_parallelism()
        .map(|parallelism| parallelism.get().min(4))
        .unwrap_or(2);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(runtime_workers)
        .thread_name("prism-runtime")
        .thread_stack_size(2 * 1024 * 1024)
        .build()
        .expect("Не удалось запустить Tokio runtime");

    runtime.block_on(async {
        tokio::spawn(async {
            if let Err(error) = matrix::media_proxy::start_media_proxy("127.0.0.1:3043").await {
                eprintln!("[Proxy] Не удалось запустить медиа-прокси: {error}");
            }
        });

        // Keep the large command-listener future off the small Windows main-thread stack.
        if let Err(error) =
            tokio::spawn(network::listener::listen_qml_commands("127.0.0.1:3042")).await
        {
            eprintln!("[Listener] Аварийное завершение: {error}");
        }
    });
}
