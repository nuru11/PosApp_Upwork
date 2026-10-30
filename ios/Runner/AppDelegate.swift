import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LocalNetworkPermissionPlugin") {
      LocalNetworkPermissionPlugin.register(with: registrar)
    }
  }
}

/// Requests and reports the iOS Local Network permission.
///
/// iOS has no API to query this permission, and plain BSD/Dart sockets do not
/// reliably show the prompt. Publishing a Bonjour service with NWListener and
/// browsing for it with NWBrowser always triggers the prompt; finding our own
/// service means "granted", while a PolicyDenied DNS error means "denied".
/// The service type must be listed under NSBonjourServices in Info.plist.
final class LocalNetworkPermissionPlugin: NSObject, FlutterPlugin {
  private static let serviceType = "_preflight_check._tcp"
  // kDNSServiceErr_PolicyDenied
  private static let policyDeniedCode: Int32 = -65570

  private var browser: NWBrowser?
  private var listener: NWListener?
  private var waiting: [FlutterResult] = []
  private var timeoutWork: DispatchWorkItem?
  // Identifies the current check so late callbacks from a cancelled one are
  // ignored instead of finishing a newer request.
  private var activeRunID: UUID?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "pos/local_network_permission",
      binaryMessenger: registrar.messenger()
    )
    let instance = LocalNetworkPermissionPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "request" else {
      result(FlutterMethodNotImplemented)
      return
    }
    waiting.append(result)
    if activeRunID == nil {
      start()
    }
  }

  private func start() {
    let runID = UUID()
    activeRunID = runID
    let newListener: NWListener
    do {
      newListener = try NWListener(using: NWParameters(tls: nil, tcp: NWProtocolTCP.Options()))
    } catch {
      finish("error", runID: runID)
      return
    }
    newListener.service = NWListener.Service(name: UUID().uuidString, type: Self.serviceType)
    // Must be set, otherwise the listener fails with POSIX error 22.
    newListener.newConnectionHandler = { connection in connection.cancel() }
    newListener.stateUpdateHandler = { [weak self] state in
      if case .failed = state {
        self?.finish("error", runID: runID)
      }
    }
    listener = newListener

    let browserParameters = NWParameters()
    browserParameters.includePeerToPeer = true
    let newBrowser = NWBrowser(
      for: .bonjour(type: Self.serviceType, domain: nil),
      using: browserParameters
    )
    newBrowser.stateUpdateHandler = { [weak self] state in
      switch state {
      case .waiting(let error):
        if case .dns(let code) = error, code == Self.policyDeniedCode {
          self?.finish("denied", runID: runID)
        }
      case .failed:
        self?.finish("error", runID: runID)
      default:
        break
      }
    }
    newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
      if !results.isEmpty {
        self?.finish("granted", runID: runID)
      }
    }
    browser = newBrowser

    // The user may leave the prompt open; report "timeout" instead of hanging.
    let work = DispatchWorkItem { [weak self] in
      self?.finish("timeout", runID: runID)
    }
    timeoutWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)

    newListener.start(queue: .main)
    newBrowser.start(queue: .main)
  }

  private func finish(_ status: String, runID: UUID) {
    guard runID == activeRunID else { return }
    activeRunID = nil
    timeoutWork?.cancel()
    timeoutWork = nil
    browser?.stateUpdateHandler = nil
    browser?.browseResultsChangedHandler = nil
    browser?.cancel()
    browser = nil
    listener?.stateUpdateHandler = nil
    listener?.cancel()
    listener = nil
    let results = waiting
    waiting.removeAll()
    for result in results {
      result(status)
    }
  }
}
