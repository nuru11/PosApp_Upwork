# Point of Sale Agent

Flutter shell for the Angular POS application. It hosts the web application and
implements the `flutter_inappwebview.callHandler('printAgent', payload)` bridge.

## Push Notifications

The app now contains an optional Firebase Cloud Messaging integration for
professional cashier-order delivery while the device is sleeping or the app is
backgrounded.

### What the Flutter app does

- Initializes `firebase_messaging` when Firebase options are supplied via
	`--dart-define`.
- Plays the system notification sound when an FCM message arrives in foreground
	or background.
- Exposes the current FCM token to the hosted web app through:
	- `window.__flutterFcmToken`
	- `window.__flutterPushBridge.getToken()`
	- `window` event `flutter-fcm-token` with payload `{ detail: { token } }`

### Required runtime configuration

Run the app with Firebase options:

```text
flutter run \
	--dart-define=FIREBASE_API_KEY=... \
	--dart-define=FIREBASE_APP_ID=... \
	--dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
	--dart-define=FIREBASE_PROJECT_ID=... \
	--dart-define=FIREBASE_STORAGE_BUCKET=...
```

Without those values, the app starts normally but FCM remains disabled.

### Required web/backend contract

The web app should read the token after login and terminal activation, then send
it to the backend so the backend can address this device with FCM.

Recommended web-side logic:

```ts
window.addEventListener('flutter-fcm-token', (event: Event) => {
	const token = (event as CustomEvent<{ token?: string }>).detail?.token;
	if (!token) return;
	// POST token, branchId, pointOfSaleId, user/session info to backend.
});

const token = (window as any).__flutterPushBridge?.getToken?.();
```

### Recommended FCM payload

Use a high-priority Android data message. Example payload body:

```json
{
	"type": "cashier-order-notification",
	"eventName": "notification.received",
	"orderId": "...",
	"branchId": "...",
	"pointOfSaleId": "...",
	"title": "طلب جديد من التطبيق",
	"message": "تم استلام طلب جديد رقم 11"
}
```

The current Flutter implementation only needs the message to arrive; it plays a
notification sound and logs message metadata.

## Run

The URL for Android, iOS, and desktop is defined once in:

```text
lib/core/config/app_config.dart
```

Change `AppConfig.webUrl` there to update every build. The current value is
`https://terminal.ragmcloud.app/`.

## iOS build (no Mac / no paid Apple account)

`.github/workflows/ios-build.yml` builds an unsigned IPA on a GitHub macOS
runner. Trigger it from the Actions tab ("Run workflow") or by pushing a tag
starting with `v`, then download the `pointofsalesapp-ios-unsigned` artifact.

Install it on an iPhone from Windows with [Sideloadly](https://sideloadly.io)
using any free Apple ID (requires iTunes + iCloud from apple.com). Free Apple ID
installs expire after 7 days and must be re-installed; enable Developer Mode on
iOS 16+ (Settings → Privacy & Security). Push notifications are unavailable on
iOS without a paid Apple Developer account.

## Print bridge

The handler accepts the existing Angular `print-html` payload. Jobs are queued
in arrival order, converted to PDF at the requested 58mm or 80mm width, and
routed exclusively by `context.target.deviceNameEn`, matching QZ Tray behavior.
There is no Sunmi-specific dependency; Sunmi is treated like any other target
printer supplied by the backend print plan.
The returned promise resolves to:

```json
{"success":true,"jobId":"...","printer":"SunmiPrinter","error":null}
```

Print failures reject the promise so the existing Angular execution service
enters its `catch` path and displays `printExecutionFailed`.

The target printer must be installed and visible to the operating system.
Direct named-printer routing is used only when the platform reports both
printer enumeration and direct-print support. A failed or missing target is
returned as an error and is never silently redirected to another kitchen.

Android and iOS do not expose silent selection of an installed system printer
by name. On these platforms the receipt is rendered with the native WebView and
the operating-system printer picker is shown. Fully silent kitchen routing on
mobile requires `ipAddress`, `port`, and `protocol` in the print-plan target (or
a vendor SDK), so the app can connect to each printer without the system picker.

Windows builds require Windows Developer Mode because Flutter plugins use
symbolic links during build. HTML-to-PDF capability is checked at runtime;
platforms that do not expose it return an explicit bridge error.

### Android network agent

For a LAN/Wi-Fi thermal printer, include network routing in the print target:

```json
{
	"deviceNameEn": "Kitchen Printer",
	"ipAddress": "192.168.100.99",
	"port": 9100,
	"protocol": "raw"
}
```

When `ipAddress` is present, the Flutter agent uses a TCP ESC/POS transport and
does not look up a system printer by name. The PDF receipt is rasterized into
ESC/POS printer commands before it is sent. `deviceNameEn` remains useful as a
label, but it is not used for network routing. When `ipAddress` is absent, the
existing named system/QZ printing path is used.