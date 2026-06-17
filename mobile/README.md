# 老照移动端

Flutter 客户端,面向家人自用。

## 本地运行

先启动后端,确认能访问:

```powershell
Invoke-RestMethod http://localhost:8000/api/health
```

安装依赖并运行:

```powershell
flutter pub get
flutter run `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 `
  --dart-define=APP_TOKEN=dev-token-change-me
```

Android 模拟器访问电脑本机后端时,把地址换成:

```powershell
--dart-define=API_BASE_URL=http://10.0.2.2:8000
```

真机调试时,把 `API_BASE_URL` 换成电脑局域网 IP 或部署后的 HTTPS 地址。

## 本地 Web 预览

推荐从项目根目录运行:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start_web_preview.ps1
```

脚本会自动启动允许当前预览端口的后端、构建 Flutter Web,并输出浏览器地址。

如果要手动排查,先用允许预览端口的 CORS 配置启动后端。下面示例把 Web 预览放在 `8082`,后端放在 `8003`:

```powershell
$env:APP_TOKEN="dev-token-change-me"
$env:CORS_ALLOW_ORIGINS="http://127.0.0.1:8082,http://localhost:8082"
cd ../backend
python -m uvicorn app.main:app --host 127.0.0.1 --port 8003
```

另开一个终端重新构建并服务 Web 文件:

```powershell
flutter build web `
  --dart-define=API_BASE_URL=http://127.0.0.1:8003 `
  --dart-define=APP_TOKEN=dev-token-change-me

cd build/web
python -m http.server 8082 --bind 127.0.0.1
```

浏览器打开 `http://127.0.0.1:8082`。如果模板页一直停在加载状态,优先检查后端 `CORS_ALLOW_ORIGINS` 是否包含当前 Web 预览端口。

## 验证

推荐用预检脚本:

```powershell
$env:APP_TOKEN="dev-token-change-me"
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1 `
  -ApiBaseUrl http://127.0.0.1:8000
```

脚本会检查:

1. `/api/health`
2. `X-App-Token` 是否能访问设备配置接口
3. 适老化红线:无会员/付费/技术错误词,硬编码字号不低于 16
4. `flutter pub get`
5. `dart analyze`
6. `flutter test`

如果只想检查 Flutter 代码,不检查后端:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/preflight.ps1 -SkipBackendCheck
```

手动验证命令:

```powershell
flutter pub get
dart analyze
flutter test
```

## 打包提示

调试包编译检查:

```powershell
flutter build apk --debug `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 `
  --dart-define=APP_TOKEN=dev-token-change-me
```

自用安装包需要显式传入后端地址和 token:

如果要使用专用 release 签名,先生成 keystore:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/create_android_keystore.ps1
```

脚本会创建 `android/keystore/lao-zhao-release.jks` 和 `android/key.properties`。`android/key.properties` 和 `android/keystore/*.jks` 已被 `.gitignore` 忽略,不要提交。

也可以用环境变量传密码,避免交互输入:

```powershell
$env:LAO_ZHAO_STORE_PASSWORD="your-store-password"
$env:LAO_ZHAO_KEY_PASSWORD="your-key-password"
powershell -ExecutionPolicy Bypass -File scripts/create_android_keystore.ps1
```

默认生成 PKCS12 keystore; 如果传入了不同的 key password,脚本会使用 store password 写入 `key.properties`,避免 Android Gradle 读取签名密钥失败。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_android_release.ps1 `
  -ApiBaseUrl https://<service>.zeabur.app `
  -AppToken your-token
```

脚本会把工程临时复制到纯英文路径构建,避开 Windows 中文目录下 release AOT 路径乱码问题。产物会放到 `dist/lao-zhao-0.1.0-release.apk`。
同时会生成 `dist/lao-zhao-0.1.0-release.apk.sha256`,方便传到手机前核对文件。
还会生成 `dist/lao-zhao-0.1.0-release.json`,记录版本、后端 URL、APK 大小和 SHA256。

安装前先验证产物:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_android_artifact.ps1
```

脚本默认会要求专用 release keystore,调用 Android SDK `apksigner` 确认 APK Signature Scheme v2 或更新签名通过,并拒绝占位地址、localhost、模拟器地址和非 HTTPS 地址,避免把连不上真实后端的 APK 发给家人。验证通过后会写出 `dist/lao-zhao-0.1.0-release.verify.json`。
只验证构建机制时才使用:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_android_release.ps1 `
  -ApiBaseUrl https://your-backend.example.com `
  -AppToken dev-token-change-me `
  -AllowPlaceholder
```

机制测试包的产物验证也需要显式放宽；如果没有专用 keystore,还要显式放宽 debug signing:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify_android_artifact.ps1 -AllowPlaceholder
# or, only for unsigned release-mechanics checks without a dedicated keystore:
powershell -ExecutionPolicy Bypass -File scripts/verify_android_artifact.ps1 -AllowPlaceholder -AllowDebugSigning
```

安装到已连接的安卓手机:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1
```

安装成功前会读取同名 `.verify.json`,确认 APK 已经过 `apksigner` 验证且 SHA256 匹配。安装成功后会写出 `dist/install_evidence.json`,用于记录真机安装证据,包括设备型号、Android 版本、安装包版本、APK 大小、SHA256 和签名验证结果。最终检查会确认 APK manifest 版本和真机安装版本与 `pubspec.yaml` 一致,并核对安装记录、manifest、verify 证据里的包名、APK 大小和 SHA256 是否一致。

如果要同时证明 App 能启动并留一张截图,加上:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1 -LaunchAfterInstall
```

脚本会启动 `com.family.photorescue.lao_zhao`,截屏到 `dist/android_launch.png`,并把截图路径写入 `dist/install_evidence.json`。截图文件必须存在且非空,否则脚本会失败。

如果连了多台设备,先看:

```powershell
adb devices
```

然后指定设备:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1 -Serial <device-id>
```

当前 Android 工程允许中文工作目录路径构建: `android.overridePathCheck=true`。如果没有 `android/key.properties`,release 构建会退回 debug 签名,仅适合自用侧载验证;正式长期分发前应配置专用 release 签名。

## iOS 真机证据

这台 Windows 环境不能执行 Xcode 构建。用 macOS/Xcode 把 App 装到 iPhone 后,回到项目目录记录证据:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/record_ios_install_evidence.ps1 `
  -DeviceModel "iPhone 15" `
  -IosVersion "18.5" `
  -AppVersion "0.1.0+1" `
  -DeviceName "家人手机" `
  -SigningTeam "Apple Team Name" `
  -ScreenshotPath "C:\path\to\ios-install-screenshot.png"
```

脚本会写出 `dist/ios_install_evidence.json`,最终 MVP 证据检查会读取它。传入的截图文件必须存在且非空,否则脚本会失败。`AppVersion` 应填写 `pubspec.yaml` 的完整版本号,例如 `0.1.0+1`。

微信直连分享需要在子女配置里填写微信开放平台 AppID；iOS 还需要有效 Universal Link 和对应工程签名配置。未配置或注册失败时,应用会自动回退系统分享。
