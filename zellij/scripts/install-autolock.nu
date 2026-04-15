http get https://api.github.com/repos/fresh2dev/zellij-autolock/releases | get 0.assets.0.browser_download_url | http get $in | save ~/.config/zellij/plugins/zellij-autolock.wasm
