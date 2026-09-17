import SwiftUI
import Flutter
import FlutterPluginRegistrant

@main
struct FireLinkApp: App {
    @UIApplicationDelegateAdaptor(FireLinkAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            FireLinkFlutterView(engine: appDelegate.flutterEngine)
                .ignoresSafeArea()
        }
    }
}

/// Flutter 引擎由原生宿主统一创建，Packet Tunnel Extension 不依赖 Flutter。
final class FireLinkAppDelegate: FlutterAppDelegate {
    let flutterEngine = FlutterEngine(name: "firelink-main")

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        flutterEngine.run()
        GeneratedPluginRegistrant.register(with: flutterEngine)
        FireLinkVpnPlugin.register(with: flutterEngine.registrar(forPlugin: "FireLinkVpnPlugin")!)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

/// UIViewControllerRepresentable 只承载 Flutter 画面，不承担 VPN 业务。
private struct FireLinkFlutterView: UIViewControllerRepresentable {
    let engine: FlutterEngine

    func makeUIViewController(context: Context) -> FlutterViewController {
        FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    }

    func updateUIViewController(_ uiViewController: FlutterViewController, context: Context) {}
}
