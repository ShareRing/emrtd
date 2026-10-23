# emrtd

NFC reader for ICAO 9303 electronic travel documents: e-passports, eID cards and residence
permits. One Rust core does all protocol work, cryptography, parsing and verification; thin
platform packages provide the NFC transport for Android and iOS, with React Native and Flutter
bindings on top.

```
app ── React Native / Flutter binding (JSON result)
        │
        ├── Android: network.sharering:emrtd-android   (IsoDep transport, EmrtdScanner)
        └── iOS:     EmrtdCore (SwiftPM / CocoaPods)    (CoreNFC transport, EmrtdScanner)
                │
                └── emrtd (Rust, UniFFI): access control, secure messaging, chip and
                    passive authentication, LDS parsing, MRZ, CSCA trust store
```

APDUs never leave native code; the host only moves bytes between the chip and the core.

## What it does

**Access control**
- PACE (9303-11 §4.4): Generic, Integrated and Chip Authentication Mapping, DH and ECDH, every
  standardized domain parameter (RFC 5114 groups, NIST P-192…P-521, brainpool P192r1…P512r1),
  3DES and AES-128/192/256. ECDH Integrated Mapping is used on curves with p ≡ 3 (mod 4). Offers
  are tried in order of strength (CAM, GM, IM; AES-256 first).
- BAC (§4.3) when PACE is not offered or the chip turns down every PACE offer, with the chip's
  cryptogram MAC and challenge echo checked.
- MRZ or CAN passwords. Peer public keys are validated (on curve, subgroup, range).

**Chip authentication** (is the chip genuine?)
- Chip Authentication v1 (§6.2), DH or ECDH, 3DES or AES; the rest of the read runs under its keys.
- PACE-CAM verification against the chip key in EF.CardSecurity (itself signature-checked), or DG14.
- Active Authentication (§6.1): RSA ISO/IEC 9796-2 and ECDSA. Pass an 8-byte challenge to get the
  signature back for server-side verification.

**Passive Authentication** (is the data genuine?) (§5.1)
- SOD signature with the signer bound to `SignerInfo.sid`; messageDigest and contentType checks.
- Document Signer certificate chained to a trusted CSCA (validity, key usage). RSA PKCS#1 v1.5,
  RSASSA-PSS, ECDSA including explicit curve parameters.
- Every data group hash checked; data groups not covered by the SOD are rejected.
- Built-in CSCA master list (878 certificates); add your own or turn it off. The result names the
  Document Signer and the matching CSCA (country, subject, issuer, validity, fingerprint).

**Data groups**: COM, SOD and DG1–DG16 (DG6 is reserved by ICAO):

| DG | Content | | DG | Content |
|---|---|---|---|---|
| 1 | MRZ (TD1, TD2, TD3, visas) | | 11 | Additional personal details |
| 2 | Face (ISO 19794-5, 39794-5) | | 12 | Additional document details |
| 3 | Fingerprints¹ | | 13 | Optional details (raw + TLV view) |
| 4 | Iris¹ | | 14 | Security options |
| 5 | Displayed portrait | | 15 | Active Authentication key |
| 7 | Signature / usual mark | | 16 | Persons to notify |
| 8–10 | Raw bytes (no defined structure) | | | EF.CardAccess, EF.CardSecurity |

¹ DG3/DG4 require Terminal Authentication with state-issued inspection-system certificates;
without them the chip denies access and the result says so.

JPEG 2000 images are converted to PNG in Rust, so every platform can display them; the original
bytes are always kept.

## Installing

Current release: **0.2.0**. The iOS frameworks are built with Xcode 26.6; build your
app with that or newer.

Minimums: Android `minSdk` 24, iOS 15. Every iOS app, React Native and Flutter ones included,
also needs the NFC capability, entitlements and Info.plist keys listed under [iOS](#ios).

### Android

From Maven Central:

```kotlin
dependencies {
    implementation("network.sharering:emrtd-android:0.2.0")
}
```

### iOS: Swift Package Manager

```swift
.package(url: "https://github.com/ShareRing/emrtd.git", from: "0.2.0")
```

Then add the `EmrtdCore` product to your target.

### iOS: CocoaPods

`EmrtdCore` is not on CocoaPods trunk. Reference the podspec attached to the release:

```ruby
pod 'EmrtdCore', :podspec => 'https://github.com/ShareRing/emrtd/releases/download/v0.2.0/EmrtdCore.podspec'
```

React Native and Flutter both depend on `EmrtdCore`, so that line belongs in the host app's
`Podfile` for those too.

### React Native

`@sharering/react-native-emrtd` is a restricted npm package: you need an npm account with
access to the `@sharering` scope.

```sh
npm install @sharering/react-native-emrtd
```

Then add the `EmrtdCore` Podfile line above and run `pod install`.

### Flutter

Published to ShareRing's private OnePub registry:

```sh
dart pub global activate onepub
onepub auth
flutter pub add emrtd
```

Then add the `EmrtdCore` Podfile line above.

If the app also embeds another Rust library as a static XCFramework, link both in a test build
early: each carries its own copy of Rust's standard library.

## Usage

### Android

Package `network.sharering.emrtd`. `scan` is a `suspend` function; call it while the activity
is resumed. The library manifest adds the `NFC` permission and an optional `android.hardware.nfc`
feature.

```kotlin
import network.sharering.emrtd.*

class ReadActivity : AppCompatActivity() {
    // Reuse the scanner: the constructor parses ReaderConfig.authorityCertificates.
    private val scanner by lazy { EmrtdScanner(this) }

    fun read() = lifecycleScope.launch {
        try {
            val doc = scanner.scan(AccessKey.Mrz("L898902C3", "740812", "120415"))
            val dataGenuine = doc.authenticationStatus.data.status == DataStatus.AUTHENTICATED
            val chipGenuine = doc.authenticationStatus.chip.status == ChipStatus.AUTHENTICATED
            val mrz = doc.machineReadableZoneInformation.fields   // MrzFields
            val name = "${mrz.secondaryIdentifier} ${mrz.primaryIdentifier}"
            val face = doc.encodedIdentificationFeaturesFace.faceImage?.toBitmap()
        } catch (e: ReadException) {
            when (e) {
                is ReadException.AccessControl -> showError("Check the MRZ data")
                is ReadException.Cancelled -> Unit
                else -> showError(readErrorMessage(e))
            }
        }
    }

    fun stop() = scanner.cancel()
}
```

Use `readErrorMessage(e)` for display text; the generated `ReadException.message` is a field
dump (`reason=…, debugInfo=…`).

### iOS

Module `EmrtdCore` (Swift Package or CocoaPods). `scan` presents the system NFC sheet.

```swift
import EmrtdCore

let scanner = EmrtdScanner(messages: ScanMessages(holdNear: "Hold the top of your iPhone on the document."))

do {
    let doc = try await scanner.scan(
        accessKey: .mrz(documentNumber: "L898902C3", dateOfBirth: "740812", dateOfExpiry: "120415")
    )
    let dataGenuine = doc.authenticationStatus.data.status == .authenticated
    let chipGenuine = doc.authenticationStatus.chip.status == .authenticated
    let mrz = doc.machineReadableZoneInformation.fields
    let face = doc.encodedIdentificationFeaturesFace.faceImage?.uiImage
} catch ReadError.AccessControl(let reason, _) {
    print("Check the MRZ data: \(reason)")
} catch ReadError.Cancelled {
    // user closed the sheet, cancel() or task cancellation
} catch let error as ReadError {
    print(readErrorMessage(error: error))
}
```

iOS apps need the *Near Field Communication Tag Reading* capability with reader session
formats `TAG` and `PACE` (`PACE` lets iOS 26.4+ find PACE-only cards), `NFCReaderUsageDescription`
and `com.apple.developer.nfc.readersession.iso7816.select-identifiers = ["A0000002471001"]` in
Info.plist.

### React Native

Package `@sharering/react-native-emrtd`. The result is the [JSON form](#naming-across-platforms)
of `TravelDocument`, typed in `types.ts`.

```ts
import { readDocument, cancel, addReadListener, parseMrz, type EmrtdError } from '@sharering/react-native-emrtd';

const sub = addReadListener((e) => {
  if (e.type === 'progress') setProgress(e.percentage);
});
try {
  const doc = await readDocument({
    accessKey: { mrz: { documentNumber: 'L898902C3', dateOfBirth: '740812', dateOfExpiry: '120415' } },
    // or: accessKey: { can: '123456' },
  });
  const dataGenuine = doc.authenticationStatus.data.status === 'authenticated';
  const chipGenuine = doc.authenticationStatus.chip.status === 'authenticated';
  const mrz = doc.machineReadableZoneInformation.fields;
  const face = doc.encodedIdentificationFeaturesFace.faceImage;
  const uri = face && (face.png ? `data:image/png;base64,${face.png}` : `data:image/jpeg;base64,${face.bytes}`);
} catch (e) {
  const { code, message } = e as EmrtdError;   // 'access_control', 'cancelled', 'busy', …
} finally {
  sub.remove();
}
```

### Flutter

Package `emrtd`. The Dart model is a reshaped, typed view of the JSON (see
[Flutter model](#flutter-model)); `doc.json` holds the full tree.

```dart
import 'package:emrtd/emrtd.dart';

final sub = Emrtd.events.listen((e) {
  if (e is ReadProgress) setState(() => progress = e.percentage);
});
try {
  final doc = await Emrtd.readDocument(
    const MrzKey(documentNumber: 'L898902C3', dateOfBirth: '740812', dateOfExpiry: '120415'),
    // or: const CanKey('123456'),
  );
  final dataGenuine = doc.dataAuthentication.isAuthenticated;
  final chipGenuine = doc.chipAuthentication.isAuthenticated;
  final name = '${doc.mrz.secondaryIdentifier} ${doc.mrz.primaryIdentifier}';
  final face = doc.faceImage == null ? null : Image.memory(doc.faceImage!.displayable);
} on EmrtdException catch (e) {
  if (e.code != EmrtdErrorCode.cancelled) showError(e.message);
} finally {
  await sub.cancel();
}
```

### Bring your own NFC stack

`EmrtdReader` runs a read over any `CardTransport`. `read` blocks, so call it off the main
thread. `IsoDepTransport` (Android) and `CoreNfcTransport` (iOS) are public and can be used with
a tag you connected yourself.

```kotlin
class MyTransport(private val link: MyLink) : CardTransport {
    override fun transceive(apdu: ByteArray): ByteArray = try {
        link.send(apdu)                       // response data + SW1 SW2
    } catch (e: MyTimeout) {
        throw TransportException.Timeout()
    } catch (e: MyLinkLost) {
        throw TransportException.TagLost()
    }
    override fun supportsExtendedLength() = link.maxApduSize > 261
}

val reader = EmrtdReader(ReaderConfig(authorityCertificates = listOf(cscaPem)))
val doc = withContext(Dispatchers.IO) {
    reader.read(MyTransport(link), AccessKey.Can("123456"), null, null)
}
```

```swift
final class MyTransport: CardTransport, @unchecked Sendable {
    let link: MyLink
    init(link: MyLink) { self.link = link }
    func transceive(apdu: Data) throws -> Data { try link.send(apdu) }   // throw TransportError.X
    func supportsExtendedLength() -> Bool { true }
}

let reader = try EmrtdReader(config: ReaderConfig())
let doc = try reader.read(transport: MyTransport(link: link), accessKey: .can(value: "123456"),
                          activeAuthenticationChallenge: nil, listener: nil)
```

Rules for a transport:

- `transceive` sends one raw command APDU and returns the raw response with SW1 SW2 appended.
  Status words such as `6982` are not errors; return them.
- The core does not apply `ReaderConfig.timeoutMs`; the transport must enforce its own timeout
  and throw `Timeout`.
- Return `true` from `supportsExtendedLength` only if the link carries extended-length APDUs.
  They are needed for large PACE/Chip Authentication keys and Active Authentication signatures
  above 1848 bits.
- `read` clears the reader's cancel flag on entry, so `cancel()` before `read` starts has no
  effect. To cancel at any time, make the transport throw `TransportError.Cancelled`.
- See [TransportError](#transporterror) for how each error surfaces.

### Interpreting the result

Data is genuine when `authenticationStatus.data.status` is authenticated (`AUTHENTICATED` in
Kotlin, `.authenticated` in Swift, `'authenticated'` in JSON). The chip is genuine when
`authenticationStatus.chip.status` is authenticated. Both are reported independently; what to
accept is the integrator's decision. `warnings` lists non-fatal problems, and
`authenticationStatus.data.errors` says why Passive Authentication did not pass.

### Passwords in memory

The core wipes its copies of the MRZ/CAN password and every derived key once a read ends.
Copies the host keeps (Kotlin/Swift/JS/Dart strings) are outside its reach.

## API reference

### Naming across platforms

The core defines every type once; UniFFI generates the Kotlin and Swift types, and the React
Native and Flutter bindings receive the document as JSON. Names in this reference use the
lowerCamel property names shared by Kotlin, Swift and JSON.

| | Kotlin | Swift | JSON (React Native, Flutter `json`) |
|---|---|---|---|
| Record | `data class TravelDocument` | `struct TravelDocument` | object |
| Property | `machineReadableZoneInformation` | `machineReadableZoneInformation` | `"machineReadableZoneInformation"` |
| Enum case | `DataStatus.AUTHORITY_CERTIFICATES_NOT_PROVIDED` | `DataStatus.authorityCertificatesNotProvided` | `"authorityCertificatesNotProvided"` |
| `ElementaryFileId` | `DG1` | `.dg1` | `"dg1"` |
| Access key | `AccessKey.Mrz(…)`, `AccessKey.Can(…)` | `.mrz(…)`, `.can(value:)` | `{ mrz: {…} }`, `{ can }` |
| Error | `ReadException.AccessControl` | `ReadError.AccessControl(reason:debugInfo:)` | `code: "access_control"` |
| Transport error | `TransportException.TagLost` | `TransportError.TagLost` | n/a |
| Bytes | `ByteArray` | `Data` | base64 string (standard alphabet, padded) |
| Optional | `T?` (`null`) | `T?` (`nil`) | `null`; the key is always present |
| List | `List<T>` | `[T]` | array |
| `u8` / `u32` / `u64` | `UByte` / `UInt` / `ULong` | `UInt8` / `UInt32` / `UInt64` | number |
| `i32` / `i64` | `Int` / `Long` | `Int32` / `Int64` | number |

Swift error enums (`ReadError`, `TransportError`) keep UpperCamel cases; all other Swift enums
are lowerCamel. Swift's `protocol` properties are declared as `` `protocol` `` but read as
`.protocol`.

Types in the tables below: `String`, `Bool`, `Bytes`, `u8`/`u32`/`u64`/`i32`/`i64` as above,
`T?` optional, `[T]` list.

### Entry points

#### Android: `EmrtdScanner`

```kotlin
class EmrtdScanner(
    activity: Activity,
    val config: ReaderConfig = ReaderConfig(),
    messages: ScanMessages? = ScanMessages(),
)

suspend fun scan(
    accessKey: AccessKey,
    activeAuthenticationChallenge: ByteArray? = null,
    listener: ReadListener? = null,
): TravelDocument

suspend fun read(
    tag: Tag,
    accessKey: AccessKey,
    activeAuthenticationChallenge: ByteArray? = null,
    listener: ReadListener? = null,
): TravelDocument

fun cancel()

data class ScanMessages(
    val title: String = "Ready to Scan",
    val holdNear: String = "Hold your device near the chip in the document.",
    val readingProgress: String = "Reading %2\$s… %1\$d%%",
    val authenticating: String = "Authenticating…",
    val success: String = "Document read.",
    val failure: String = "Could not read the document.",
    val cancel: String = "Cancel",
)

fun DocumentImage.toBitmap(): Bitmap?   // Images.kt
```

| Member | Behaviour |
|---|---|
| constructor | Builds an `EmrtdReader`. Throws `ReadException.InvalidArgument` when `config.authorityCertificates` cannot be loaded. Reuse one scanner. |
| `scan` | Turns on NFC reader mode (NFC-A/B, no NDEF check, no platform sounds), waits for the first `IsoDep` tag, reads it and turns reader mode off however the read ends. Throws `ReadException.NfcUnavailable` when the device has no NFC or it is off. The read runs on `Dispatchers.IO`. Shows a bottom sheet (title, status text, Cancel) like the iOS NFC sheet while it runs, light or dark with the activity's night mode, unless `messages` is `null`; Cancel and Back end the scan with `ReadException.Cancelled`. |
| `read` | Reads a tag the app obtained itself (foreground dispatch, intent). Throws `IllegalArgumentException` if the tag is not `IsoDep`. |
| `cancel` | Ends the `scan` or `read` in progress with `ReadException.Cancelled`, whether it is still waiting for a tag or mid-read. |
| coroutine cancellation | Cancelling the calling coroutine stops the read and rethrows `CancellationException`. |
| `ScanMessages.readingProgress` | `String.format` pattern; `%1$d` is the total progress 0-100, `%2$s` the file being read (`DG2`). The other fields as on iOS, plus the sheet's `title` and `cancel` button text. |
| `toBitmap` | Decodes `png ?: bytes`; `null` when undecodable (WSQ). |

The scanner applies `config.timeoutMs` as the `IsoDep` timeout. One `scan` or `read` at a time:
a second one while one runs throws `ReadException.InvalidArgument("A scan is already in progress")`.

#### iOS: `EmrtdScanner`, `ScanMessages`

```swift
public final class EmrtdScanner {
    public let config: ReaderConfig
    public init(config: ReaderConfig = ReaderConfig(), messages: ScanMessages = ScanMessages())
    public func scan(accessKey: AccessKey,
                     activeAuthenticationChallenge: Data? = nil,
                     listener: ReadListener? = nil) async throws -> TravelDocument
    public func cancel()
}

public struct ScanMessages: Sendable {
    public init(holdNear: String = "Hold your iPhone near the chip in the document.",
                readingProgress: String = "Reading %2$@… %1$d%%",
                authenticating: String = "Authenticating…",
                success: String = "Document read.",
                failure: String = "Could not read the document.")
}

extension DocumentImage { public var uiImage: UIImage? }   // Images.swift
```

| Member | Behaviour |
|---|---|
| `init` | Does not throw. The reader (and `config.authorityCertificates`) is built at each `scan`. |
| `scan` | Presents the NFC sheet (polling ISO 14443, plus PACE on iOS 26.4+), reads the first ISO 7816 tag and closes the sheet. Every failure is a `ReadError`. A second call while one runs throws `ReadError.InvalidArgument("A scan is already in progress")`. Retries up to twice, one second apart, when CoreNFC reports the system busy. `listener` is called on a background thread. |
| `cancel` | Ends the scan in progress with `ReadError.Cancelled`. Cancelling the calling `Task` does the same. |
| `ScanMessages.holdNear` | Sheet text while waiting for a tag. |
| `ScanMessages.readingProgress` | `String(format:)` pattern; `%1$d` is the total progress 0-100, `%2$@` the file being read (`DG2`). |
| `ScanMessages.authenticating` | Shown when access control starts. |
| `ScanMessages.success` / `failure` | Shown when the sheet closes. |
| `uiImage` | `UIImage(data: png ?? bytes)`; `nil` for WSQ. |

`CoreNfcTransport(tag: NFCISO7816Tag, timeoutMs: UInt32 = 5000)` is the transport the scanner
uses, with `close()` to fail pending and later commands with `Cancelled`. Never call its
`transceive` on the session's delegate queue.

#### React Native

```ts
function readDocument(options: ReadOptions): Promise<TravelDocument>;
function cancel(): void;
function parseMrz(lines: string[]): Promise<MachineReadableZone>;
function addReadListener(listener: (event: ReadEvent) => void): EmitterSubscription;

type AccessKey =
  | { mrz: { documentNumber: string; dateOfBirth: string; dateOfExpiry: string } }
  | { can: string };

type ReadErrorKind = 'readingDataGroups' | 'parseMasterFile' | 'unknown';

interface EmrtdError extends Error {
  code: EmrtdErrorCode;
  reason: string | null;          // the underlying reason, without the message prefix
  kind: ReadErrorKind | null;     // `read` errors only
  debugInfo: DebugInfo | null;    // the read log when `debug` was on
}
```

`ReadOptions`:

| Field | Type | Default | Meaning |
|---|---|---|---|
| `accessKey` | `AccessKey` | required | MRZ data or CAN. |
| `activeAuthenticationChallenge` | `string` (base64) | none | 8 random bytes; the signature comes back in `authenticationStatus.chip.activeAuthenticationResponse`. |
| `useBuiltInAuthorityCertificates` | `boolean` | `true` | Trust the built-in CSCA list. |
| `authorityCertificatesPem` | `string` | none | One PEM bundle of extra CSCA certificates. |
| `timeoutMs` | `number` | `5000` | NFC transceive timeout. |
| `debug` | `boolean` | `false` | Fill `debugInfo.events`. |

`ReadEvent` (from `addReadListener`):

| `type` | Extra fields | Listener method |
|---|---|---|
| `'accessStarted'` | | `onAccessEstablishmentStarted` |
| `'progress'` | `id: ElementaryFileId`, `percentage: number` | `onElementaryFilesReadingProgressUpdated` |
| `'dataAuthenticationStarted'` | | `onDataAuthenticationStarted` |

One read at a time: a second `readDocument` while one runs rejects with `busy`. On Android the
read uses the current foreground activity. `parseMrz` rejects with `invalid_argument` on
malformed input. `types.ts` exports a TypeScript type for every record in
[TravelDocument](#traveldocument) and for `MachineReadableZone`.

#### Flutter

```dart
class Emrtd {
  static Stream<ReadEvent> get events;
  static Future<TravelDocument> readDocument(
    AccessKey accessKey, {
    Uint8List? activeAuthenticationChallenge,
    bool useBuiltInAuthorityCertificates = true,
    String? authorityCertificatesPem,
    int timeoutMs = 5000,
    bool debug = false,
  });
  static Future<void> cancel();
  static Future<MachineReadableZone> parseMrz(List<String> lines);
}

sealed class AccessKey;
class MrzKey extends AccessKey { const MrzKey({required String documentNumber, required String dateOfBirth, required String dateOfExpiry}); }
class CanKey extends AccessKey { const CanKey(String value); }

class EmrtdException implements Exception {
  final EmrtdErrorCode code;
  final String message;
  final String? reason;               // the underlying reason, without the message prefix
  final String? kind;                 // `read` errors only: readingDataGroups, parseMasterFile, unknown
  final List<DebugEvent> debugEvents; // the read log when `debug` was on
}
enum EmrtdErrorCode { invalidArgument, accessControl, chipAuthentication, notConnected, read, cancelled, nfcUnavailable, busy, unknown }

sealed class ReadEvent;
class AccessStarted extends ReadEvent {}
class ReadProgress extends ReadEvent { final String fileId; final int percentage; }
class DataAuthenticationStarted extends ReadEvent {}
```

The options mean the same as in React Native. `readDocument` and `parseMrz` throw
`EmrtdException`; a second `readDocument` while one runs throws `busy`. `ReadProgress.fileId` is
the JSON `ElementaryFileId` (`dg2` …).

#### `EmrtdReader` (all native platforms)

```kotlin
class EmrtdReader(config: ReaderConfig) : AutoCloseable           // throws ReadException.InvalidArgument
fun read(transport: CardTransport, accessKey: AccessKey,
         activeAuthenticationChallenge: ByteArray?, listener: ReadListener?): TravelDocument
fun cancel()
```

```swift
public convenience init(config: ReaderConfig) throws
public func read(transport: CardTransport, accessKey: AccessKey,
                 activeAuthenticationChallenge: Data?, listener: ReadListener?) throws -> TravelDocument
public func cancel()
```

| Member | Behaviour |
|---|---|
| constructor | Loads `config.authorityCertificates`; `InvalidArgument("Unable to load authority certificates")` if an entry yields no certificate. Create one per configuration and reuse it. |
| `read` | Runs a full read over `transport`. Blocking. One read at a time per reader. `activeAuthenticationChallenge`, when given, must be 8 bytes. Wipes its copy of `accessKey` when done. |
| `cancel` | Aborts the read in progress; it fails with `Cancelled` before the next APDU. Applies only to a read already running. |

#### `CardTransport`

| Method | Kotlin | Swift | Meaning |
|---|---|---|---|
| `transceive` | `fun transceive(apdu: ByteArray): ByteArray` | `func transceive(apdu: Data) throws -> Data` | Send one command APDU; return response data plus SW1 SW2. Throw `TransportException` / `TransportError` on link failure. |
| `supportsExtendedLength` | `fun supportsExtendedLength(): Boolean` | `func supportsExtendedLength() -> Bool` | Whether extended-length APDUs can be sent. |

### ReadListener

Implemented by the host. All methods are called on the reading thread, in this order.

| Method | When |
|---|---|
| `onAccessEstablishmentStarted()` | The read started; BAC or PACE is about to run. |
| `onElementaryFilesReadingProgressUpdated(id: ElementaryFileId, totalProgressPercentage: i32)` | Bytes of a data group were read. The percentage (0-100) covers EF.COM, EF.SOD and every readable data group together, by size; `id` is the file being read. The first call reports `SOD` once EF.COM and EF.SOD are in, and a final call reports 100. |
| `onDataAuthenticationStarted()` | All files are read; parsing and Passive Authentication start. |

Kotlin: `totalProgressPercentage: Int`; Swift: `Int32`.

### Free functions

Kotlin top-level functions in `network.sharering.emrtd`; Swift global functions in `EmrtdCore`.
Not exposed by the React Native and Flutter bindings, except `parseMrz`.

| Function | Kotlin | Swift | Meaning |
|---|---|---|---|
| `parseMrz` | `parseMrz(lines: List<String>): MachineReadableZone` | `parseMrz(lines: [String]) throws -> MachineReadableZone` | Parse MRZ lines, e.g. from OCR. Lines are trimmed and uppercased; 3×30 is TD1, 2×36 TD2 (MRV-B if it starts with `V`), 2×44 TD3 (MRV-A if it starts with `V`). Throws `InvalidArgument` on other characters, unequal line lengths or another layout. |
| `accessKeyFromMrz` | `accessKeyFromMrz(mrz: MachineReadableZone): AccessKey` | `accessKeyFromMrz(mrz:) -> AccessKey` | The `AccessKey.Mrz` printed in a parsed MRZ (document number including any TD1/TD2 overflow, raw dates). |
| `travelDocumentToJson` | `travelDocumentToJson(document: TravelDocument): String` | `travelDocumentToJson(document:) -> String` | The document as JSON, as the React Native and Flutter bindings receive it. |
| `machineReadableZoneToJson` | `machineReadableZoneToJson(mrz: MachineReadableZone): String` | `machineReadableZoneToJson(mrz:) -> String` | A `MachineReadableZone` as JSON, same shape as inside the document. |
| `certificateInfos` | `certificateInfos(pemOrDer: ByteArray): List<CertificateInfo>` | `certificateInfos(pemOrDer: Data) -> [CertificateInfo]` | Describe the certificates in a PEM bundle or DER blob; empty when none parse. |
| `readErrorMessage` | `readErrorMessage(error: ReadException): String` | `readErrorMessage(error: ReadError) -> String` | Human-readable text for an error. |
| `readErrorToJson` | `readErrorToJson(error: ReadException): String` | `readErrorToJson(error: ReadError) -> String` | An error as JSON: `code` (snake_case), `message`, `reason`, `kind` and `debugInfo` (`null` where the variant has none). The React Native and Flutter bindings use it to pass errors on in full. |
| `readOutcome` | `readOutcome(document: TravelDocument?, error: ReadException?, durationMs: ULong): ReadOutcome` | `readOutcome(document:error:durationMs: UInt64) -> ReadOutcome` | Analytics summary of a read; pass the document or the error. See [ReadOutcome](#readoutcome). |
| `readOutcomeToJson` | `readOutcomeToJson(outcome: ReadOutcome): String` | `readOutcomeToJson(outcome:) -> String` | `ReadOutcome` as JSON. |

### ReaderConfig

| Field | Type | Default | Meaning |
|---|---|---|---|
| `useBuiltInAuthorityCertificates` | `Bool` | `true` | Trust the CSCA master list built into the library. |
| `authorityCertificates` | `[Bytes]` | `[]` | Additional trusted CSCA certificates. Each entry is a PEM bundle (any number of certificates) or one DER certificate. An entry with no loadable certificate fails the reader's construction with `InvalidArgument`. |
| `timeoutMs` | `u32` | `5000` | NFC transceive timeout in milliseconds, applied by the platform transport (`IsoDep.timeout` on Android, per command on iOS). Custom transports must apply it themselves. |
| `debug` | `Bool` | `false` | Record a log of every step and APDU in `debugInfo` (on the document and on errors). Secrets are redacted. |

With `useBuiltInAuthorityCertificates = false` and no `authorityCertificates`, no CSCA is
trusted and `data.status` is at best `authorityCertificatesNotProvided`.

### AccessKey

| Variant | Kotlin | Swift | Fields |
|---|---|---|---|
| MRZ | `AccessKey.Mrz(documentNumber, dateOfBirth, dateOfExpiry)` | `.mrz(documentNumber:dateOfBirth:dateOfExpiry:)` | Opens the chip with BAC or PACE. |
| CAN | `AccessKey.Can(value)` | `.can(value:)` | Opens the chip with PACE only. |

Accepted input, validated before anything is sent to the chip (`InvalidArgument` otherwise):

| Field | Format |
|---|---|
| `documentNumber` | The full document number without check digit. Trimmed and uppercased; letters `A-Z`, digits and `<` only. Numbers shorter than 9 characters are padded with `<`; longer numbers (TD1/TD2 overflow) are used whole. |
| `dateOfBirth`, `dateOfExpiry` | `YYMMDD` as printed in the MRZ: exactly 6 characters of digits or `<` (unknown parts), after trimming. |
| `value` (CAN) | Exactly 6 digits, after trimming. |

A CAN on a document without PACE fails with `AccessControl`. When PACE fails before mutual
authentication and the key is MRZ, the reader falls back to BAC and adds a warning.

### TravelDocument

`TravelDocument` is the result of a read. Optional data groups are `null` when the file is
absent, access was denied, or it could not be parsed (then with a message in `warnings`).

| Property | Type | Source | Meaning |
|---|---|---|---|
| `ldsMasterFile` | [`LdsMasterFile`](#ldsmasterfile) | | Raw bytes of every file read. |
| `ldsVersion` | `String` | EF.COM | LDS version, e.g. `1.7`. |
| `unicodeVersion` | `String?` | EF.COM | Unicode version, e.g. `4.0.0`. |
| `accessControlProtocolUsed` | [`AccessControlProtocol`](#enums) | | BAC or PACE. |
| `paceMapping` | [`PaceMapping?`](#enums) | | Set when PACE was used. |
| `authenticationStatus` | [`AuthenticationStatus`](#authenticationstatus) | | Data and chip authentication results. |
| `machineReadableZoneInformation` | [`MachineReadableZoneInformation`](#machinereadablezoneinformation) | DG1 | The MRZ. |
| `encodedIdentificationFeaturesFace` | [`EncodedIdentificationFeaturesFace`](#encodedidentificationfeaturesface) | DG2 | Face. Always present; empty when DG2 could not be parsed. |
| `encodedIdentificationFeaturesFinger` | [`EncodedIdentificationFeatures?`](#encodedidentificationfeatures) | DG3 | Fingerprints. Normally `null`: access needs Terminal Authentication. |
| `encodedIdentificationFeaturesIris` | [`EncodedIdentificationFeatures?`](#encodedidentificationfeatures) | DG4 | Iris. Normally `null`, as DG3. |
| `displayedPortrait` | [`DisplayedPortrait?`](#displayedportrait-displayedsignatureorusualmark) | DG5 | Displayed portrait. |
| `displayedSignatureOrUsualMark` | [`DisplayedSignatureOrUsualMark?`](#displayedportrait-displayedsignatureorusualmark) | DG7 | Signature or usual mark. |
| `additionalPersonalDetails` | [`AdditionalPersonalDetails?`](#additionalpersonaldetails) | DG11 | |
| `additionalDocumentDetails` | [`AdditionalDocumentDetails?`](#additionaldocumentdetails) | DG12 | |
| `optionalDetails` | [`OptionalDetails?`](#optionaldetails) | DG13 | |
| `securityOptions` | [`SecurityOptions?`](#securityoptions-securityinfo) | DG14 | |
| `activeAuthenticationPublicKeyInfo` | [`PublicKeyInfo?`](#publickeyinfo) | DG15 | Active Authentication public key. |
| `personsToNotify` | [`PersonsToNotify?`](#personstonotify-persontonotify) | DG16 | |
| `warnings` | `[String]` | | Non-fatal problems: a data group that could not be parsed, PACE falling back to BAC, Active Authentication failing, EF.CardSecurity unreadable. |
| `debugInfo` | [`DebugInfo`](#debuginfo-debugevent) | | Debug log; `events` is empty unless `ReaderConfig.debug`. |

DG8–DG10 have no defined structure; their bytes are in `ldsMasterFile`.

#### LdsMasterFile

| Property | Type | Meaning |
|---|---|---|
| `lds1EmrtdApplication` | [`Lds1EmrtdApplication`](#lds1emrtdapplication) | The files of the eMRTD application. |
| `cardAccess` | `Bytes?` | EF.CardAccess (PACE parameters), when present. |
| `cardSecurity` | `Bytes?` | EF.CardSecurity, read only for PACE-CAM. |

#### Lds1EmrtdApplication

| Property | Type | Meaning |
|---|---|---|
| `com`, `sod`, `dg1`, `dg2` | [`ElementaryFile`](#elementaryfile) | Mandatory; always read (a read without them fails). |
| `dg3`, `dg4`, `dg5`, `dg7`, `dg8`, `dg9`, `dg10`, `dg11`, `dg12`, `dg13`, `dg14`, `dg15`, `dg16` | [`ElementaryFile?`](#elementaryfile) | `null` when the file is not on the chip; an `ElementaryFile` with `bytes = null` when access was denied. |

The reader tries the data groups listed in EF.COM or hashed in EF.SOD, plus DG1, DG2, DG14 and
DG15. DG3/DG4 are tried last; a refusal or a dropped channel records them as denied.

#### ElementaryFile

| Property | Type | Meaning |
|---|---|---|
| `id` | [`ElementaryFileId`](#enums) | Which file. |
| `bytes` | `Bytes?` | The complete file, outer tag and length included; `null` when the chip denied access (SW `6982`). |

#### DocumentImage

| Property | Type | Meaning |
|---|---|---|
| `format` | [`ImageFormat`](#enums) | Detected from the bytes, else taken from the ISO 19794 / 39794 image header. |
| `size` | `ImageSize` | `width: u32`, `height: u32`. From the biometric header, else decoded from the image (JPEG, PNG, JPEG 2000); `0×0` when unknown. |
| `bytes` | `Bytes` | The image exactly as stored on the chip. |
| `png` | `Bytes?` | A PNG rendering of a JPEG 2000 image; `null` for other formats or when decoding failed. |

To display: `png ?? bytes`. Helpers: Kotlin `toBitmap()`, Swift `uiImage`, Flutter
`displayable`. WSQ (fingerprints) cannot be displayed by the platforms.

#### BiometricRecord

One CBEFF biometric record (ISO/IEC 7816-11) from DG2, DG3 or DG4.

| Property | Type | Meaning |
|---|---|---|
| `biometricType` | `u32?` | Biometric type (header tag `81`). |
| `biometricSubtype` | `u32?` | Biometric subtype (tag `82`). |
| `formatOwner` | `u32?` | Format owner (tag `87`). |
| `formatType` | `u32?` | Format type (tag `88`). |
| `images` | [`[DocumentImage]`](#documentimage) | Images found in the biometric data block. |
| `data` | `Bytes` | The raw biometric data block. |

#### EncodedIdentificationFeaturesFace

| Property | Type | Meaning |
|---|---|---|
| `faceImage` | [`DocumentImage?`](#documentimage) | The first image of the first record, which ICAO requires to be the interoperable one. |
| `records` | [`[BiometricRecord]`](#biometricrecord) | All face records. |

#### EncodedIdentificationFeatures

| Property | Type | Meaning |
|---|---|---|
| `records` | [`[BiometricRecord]`](#biometricrecord) | Fingerprint (DG3) or iris (DG4) records. |

#### DisplayedPortrait, DisplayedSignatureOrUsualMark

| Record | Property | Type | Meaning |
|---|---|---|---|
| `DisplayedPortrait` | `displayedPortraitImage` | [`DocumentImage?`](#documentimage) | DG5 image (tag `5F40`). |
| `DisplayedSignatureOrUsualMark` | `displayedSignatureOrUsualMarkImage` | [`DocumentImage?`](#documentimage) | DG7 image (tag `5F43`). |

#### AdditionalPersonalDetails

DG11. Every field is optional on the chip.

| Property | Type | Meaning |
|---|---|---|
| `nameOfHolder` | `NameOfHolder?` | `primaryIdentifier: String?`, `secondaryIdentifier: String?`: the full name in national characters. |
| `otherNames` | `[String]` | Other names. |
| `personalNumber` | `String?` | Personal number. |
| `fullDateOfBirth` | `String?` | `YYYYMMDD`, with `00` for unknown parts. |
| `placeOfBirth` | `[String]?` | Place of birth, as lines. |
| `address` | `[String]?` | Address lines, empty lines kept. |
| `telephone` | `String?` | Telephone. |
| `profession` | `String?` | Profession. |
| `title` | `String?` | Title. |
| `personalSummary` | `String?` | Personal summary. |
| `proofOfCitizenship` | [`DocumentImage?`](#documentimage) | Proof of citizenship image. |
| `otherValidTravelDocumentNumbers` | `[String]?` | Other valid travel document numbers. |
| `custodyInformation` | `String?` | Custody information. |

#### AdditionalDocumentDetails

DG12.

| Property | Type | Meaning |
|---|---|---|
| `issuingAuthority` | `String?` | Issuing authority. |
| `dateOfIssue` | `String?` | `YYYYMMDD`. |
| `otherPersonDetails` | `[String]?` | Names of other persons on the document. |
| `endorsementsOrObservations` | `String?` | Endorsements and observations. |
| `taxOrExitRequirements` | `String?` | Tax or exit requirements. |
| `imageOfFront` | [`DocumentImage?`](#documentimage) | Image of the document front. |
| `imageOfRear` | [`DocumentImage?`](#documentimage) | Image of the document rear. |
| `personalizationTime` | `String?` | `YYYYMMDDhhmmss`. |
| `personalizationDeviceSerialNumber` | `String?` | Serial number of the personalization system. |

#### OptionalDetails

DG13, whose content is at the issuer's discretion.

| Property | Type | Meaning |
|---|---|---|
| `content` | `Bytes` | Value of the `6D` object. |
| `fields` | `[TagValue]` | A flat, non-recursive TLV view of `content` (`tag: u32`, `value: Bytes`); empty when `content` is not TLV. |

#### PersonsToNotify, PersonToNotify

DG16. `PersonsToNotify.persons: [PersonToNotify]`.

| Property | Type | Meaning |
|---|---|---|
| `dateRecorded` | `String?` | `YYYYMMDD`. |
| `name` | `String?` | Name of the person to notify. |
| `telephone` | `String?` | Telephone. |
| `address` | `String?` | Address. |

#### SecurityOptions, SecurityInfo

DG14. `SecurityOptions.securityInfos: [SecurityInfo]`.

| Property | Type | Meaning |
|---|---|---|
| `protocol` | `String` | Protocol OID. |
| `name` | `String` | Protocol name, e.g. `id-CA-ECDH-AES-CBC-CMAC-128`. |
| `version` | `i64?` | Protocol version. |
| `keyId` | `i64?` | Key identifier, when the chip has several keys. |
| `parameterId` | `i64?` | Standardized domain parameter id (PACE). |

#### PublicKeyInfo

DG15.

| Property | Type | Meaning |
|---|---|---|
| `algorithm` | `String` | `RSA`, `EC` or `DH`. |
| `keySize` | `u32` | Key size in bits. |
| `curve` | `String?` | Curve name for EC keys; `explicit` when the parameters match no standard curve. |
| `der` | `Bytes` | DER SubjectPublicKeyInfo. |

#### AuthenticationStatus

| Property | Type | Meaning |
|---|---|---|
| `data` | [`DataAuthenticationStatus`](#dataauthenticationstatus) | Passive Authentication: is the data genuine and unaltered? |
| `chip` | [`ChipAuthenticationStatus`](#chipauthenticationstatus) | Chip, PACE-CAM or Active Authentication: is the chip genuine (not cloned)? |

#### DataAuthenticationStatus

| Property | Type | Meaning |
|---|---|---|
| `status` | [`DataStatus`](#enums) | The verdict; see below. |
| `protocol` | [`DataProtocol`](#enums) | Always `passiveAuthentication`. |
| `sodSignatureValid` | `Bool` | The SOD signature verifies with the Document Signer certificate. |
| `certificateChainValid` | `Bool` | The Document Signer certificate chains to a trusted CSCA, was issued within the CSCA's validity, is valid now and has the digitalSignature key usage. |
| `dataGroupHashesValid` | `Bool` | Every data group that was read matches its SOD hash, and none was read without one. |
| `dataGroupHashes` | `[DataGroupHash]` | Per data group, sorted by number: `dataGroupNumber: u8`, `status:` [`HashStatus`](#enums). |
| `hashAlgorithm` | `String?` | Hash algorithm of the SOD, e.g. `SHA-256`. |
| `signatureAlgorithm` | `String?` | Signature algorithm of the SOD. |
| `documentSignerCertificate` | [`CertificateInfo?`](#certificateinfo) | The Document Signer certificate from the SOD, bound to `SignerInfo.sid`. |
| `countrySigningCertificate` | [`CertificateInfo?`](#certificateinfo) | The trusted CSCA that issued the Document Signer certificate; `null` when none matched. |
| `issuingCountry` | `String?` | ISO 3166-1 alpha-2 country of the Document Signer (subject `C`, else issuer `C`). |
| `errors` | `[String]` | Why authentication failed, when it did. |

`status` is `denied` when the SOD signature or any hash is invalid; otherwise `authenticated`
when the chain is valid, `authorityCertificatesNotProvided` when no trusted CSCA names the
Document Signer's issuer, and `denied` for any other chain failure (expired Document Signer,
signature not verifying, key usage).

#### ChipAuthenticationStatus

| Property | Type | Meaning |
|---|---|---|
| `status` | [`ChipStatus`](#enums) | The verdict; see below. |
| `protocol` | [`ChipProtocol?`](#enums) | The protocol behind `status`; `null` when `notSupported`. |
| `activeAuthentication` | [`ChipStatus?`](#enums) | Result of Active Authentication when it ran, alongside or instead of Chip Authentication. |
| `activeAuthenticationResponse` | `Bytes?` | The chip's signature over the caller's challenge, when one was supplied and it verified. A server can re-verify it with DG15. |

How `status` is decided:
- Active Authentication runs when DG15 holds a key and either a challenge was supplied or
  neither Chip Authentication nor PACE-CAM ran.
- If Active Authentication is `denied`, `status` is `denied` with protocol `activeAuthentication`.
- Otherwise PACE-CAM (`paceChipAuthenticationMapping`) or Chip Authentication
  (`chipAuthentication`) decides, unless it is `notSupported`.
- Otherwise Active Authentication's result decides; with none of them, `notSupported`.

A Chip Authentication failure is not a status: the read fails with `ChipAuthentication`.

#### CertificateInfo

Used for the Document Signer and the CSCA, and returned by `certificateInfos`.

| Property | Type | Meaning |
|---|---|---|
| `subject` | `String` | Subject, RFC 4514 style distinguished name. |
| `issuer` | `String` | Issuer, RFC 4514 style. |
| `country` | `String?` | ISO 3166-1 alpha-2 country of the subject (`C`), uppercased. |
| `organization` | `String?` | Subject `O`. |
| `commonName` | `String?` | Subject `CN`. |
| `serialNumber` | `String` | Uppercase hex. |
| `notBefore` | `String` | ISO 8601 UTC, e.g. `2020-01-01T00:00:00Z`. |
| `notAfter` | `String` | ISO 8601 UTC. |
| `signatureAlgorithm` | `String` | Certificate signature algorithm. |
| `publicKeyAlgorithm` | `String` | `RSA`, `EC` …, or the key OID when the key is not understood. |
| `publicKeySize` | `u32` | Key size in bits; 0 when unknown. |
| `subjectKeyIdentifier` | `String?` | Uppercase hex. |
| `authorityKeyIdentifier` | `String?` | Uppercase hex. |
| `sha256Fingerprint` | `String` | Uppercase hex SHA-256 of the DER encoding. |
| `der` | `Bytes` | The certificate, DER. |

#### MachineReadableZoneInformation

| Property | Type | Meaning |
|---|---|---|
| `machineReadableZone` | [`MachineReadableZone`](#machinereadablezone) | The parsed MRZ with positions and check digits. |
| `fields` | [`MrzFields`](#mrzfields) | The fields every layout has, flattened. |

#### MrzFields

| Property | Type | Meaning |
|---|---|---|
| `documentCode` | `String` | E.g. `P`, `I`, `ID`, `V`. |
| `issuingState` | `String` | Issuing state or organization code, fillers removed (e.g. `UTO`, `D`). |
| `documentNumber` | `String` | Document (passport) number, overflow included, fillers removed. |
| `primaryIdentifier` | `String?` | Surname(s). |
| `secondaryIdentifier` | `String?` | Given name(s). |
| `nationality` | `String` | Nationality code, fillers removed. |
| `dateOfBirth` | `String` | `YYMMDD` as printed. |
| `sex` | `String` | `M`, `F`, `X` or `<` (unspecified), as printed. |
| `dateOfExpiry` | `String` | `YYMMDD` as printed. |
| `optionalData` | `String?` | Optional data (TD1: both fields joined by a space; TD3: personal number). |
| `checkDigitsValid` | `Bool` | All check digits, composite included, are valid. |

#### MachineReadableZone

Exactly one of `td1`, `td2`, `td3` is set.

| Property | Type | Meaning |
|---|---|---|
| `lines` | `[String]` | The MRZ lines, uppercased. |
| `travelDocumentType` | [`TravelDocumentType`](#enums) | Layout. |
| `td1` | `Td1MachineReadableZone?` | 3 lines of 30 (ID cards). |
| `td2` | `Td2MachineReadableZone?` | 2 lines of 36 (TD2, MRV-B visas). |
| `td3` | `Td3MachineReadableZone?` | 2 lines of 44 (passports, MRV-A visas). |

Layout records. Element types are described after the table.

| Property | TD1 | TD2 | TD3 |
|---|---|---|---|
| `documentCode` | `Element` | `Element` | `Element` |
| `issuingStateOrOrganization` | `Element` | `Element` | `Element` |
| `name` | `NameElement` | `NameElement` | `NameElement` |
| `documentNumber` | `ElementWithCheckDigit` | `ElementWithCheckDigit` | n/a |
| `passportNumber` | n/a | n/a | `ElementWithCheckDigit` |
| `nationality` | `Element` | `Element` | `Element` |
| `dateOfBirth` | `DateElementWithCheckDigit` | `DateElementWithCheckDigit` | `DateElementWithCheckDigit` |
| `sex` | `Element` | `Element` | `Element` |
| `dateOfExpiry` | `DateElementWithCheckDigit` | `DateElementWithCheckDigit` | `DateElementWithCheckDigit` |
| `optionalData` | `[Element]` (line 1 and line 2 optional data) | `Element?` | n/a |
| `personalNumberOrOtherOptionalData` | n/a | n/a | `ElementWithCheckDigit`; for MRV-A visas plain optional data with an empty `checkDigit.value` |
| `compositeCheckDigit` | `CheckDigit` | `CheckDigit?` (`null` for MRV-B) | `CheckDigit?` (`null` for MRV-A) |

| Record | Property | Type | Meaning |
|---|---|---|---|
| `Element` | `value` | `String` | Trailing fillers removed, inner fillers replaced by spaces. |
| | `raw` | `String` | The text exactly as printed. |
| | `positions` | `[StringPosition]` | Where `raw` is printed (several ranges for a document number overflow). |
| `ElementWithCheckDigit` | `value`, `raw`, `positions` | | As `Element`. |
| | `checkDigit` | `CheckDigit` | Its check digit. |
| `DateElementWithCheckDigit` | `date` | `MrzDate` | The parsed date. |
| | `value`, `raw`, `positions`, `checkDigit` | | As `ElementWithCheckDigit`. |
| `NameElement` | `primaryIdentifier` | `Element?` | Surname(s). |
| | `secondaryIdentifier` | `Element?` | Given name(s). |
| `CheckDigit` | `isValid` | `Bool` | The check digit matches the raw text. |
| | `value` | `String` | The character as printed. |
| `MrzDate` | `year`, `month`, `day` | `u32?` | Two-digit parts exactly as printed; `null` for unknown (`<`) parts. No century is inferred. |
| `StringPosition` | `lineIndex` | `u32` | 0-based line. |
| | `startIndex`, `endIndex` | `u32` | Inclusive 0-based columns. |

#### DebugInfo, DebugEvent

| Record | Property | Type | Meaning |
|---|---|---|---|
| `DebugInfo` | `events` | `[DebugEvent]` | Defaults to empty; filled only when `ReaderConfig.debug` is on. |
| `DebugEvent` | `timestampMillis` | `u64` | Milliseconds since the read started. |
| | `message` | `String` | A step or an APDU, secrets redacted. |

Errors carry a `DebugInfo` too. Errors raised by the platform layer before the core runs
(connection, sheet dismissal) carry an empty one.

#### Flutter model

Flutter decodes the JSON into a smaller typed model. Enums are plain strings with the JSON
values; bytes are `Uint8List`. `TravelDocument.json` and `MachineReadableZone.json` keep the
full JSON tree.

| Flutter `TravelDocument` | JSON path |
|---|---|
| `ldsMasterFile.files` (`Map<String, ElementaryFile>`, only files present), `.cardAccess`, `.cardSecurity` | `ldsMasterFile` |
| `ldsVersion`, `unicodeVersion`, `accessControlProtocolUsed`, `paceMapping`, `warnings` | same |
| `dataAuthentication` (with `isAuthenticated`) | `authenticationStatus.data` |
| `chipAuthentication` (with `isAuthenticated`) | `authenticationStatus.chip` |
| `machineReadableZone` (`lines`, `travelDocumentType`, `td1`/`td2`/`td3`, `json`) | `machineReadableZoneInformation.machineReadableZone` |
| `mrz` (`MrzFields`) | `machineReadableZoneInformation.fields` |
| `faceImage`, `faceRecords` | `encodedIdentificationFeaturesFace.faceImage`, `.records` |
| `fingerRecords`, `irisRecords` | `encodedIdentificationFeaturesFinger.records`, `encodedIdentificationFeaturesIris.records` |
| `displayedPortrait`, `displayedSignature` | `displayedPortrait.displayedPortraitImage`, `displayedSignatureOrUsualMark.displayedSignatureOrUsualMarkImage` |
| `additionalPersonalDetails` (`primaryIdentifier`, `secondaryIdentifier` flattened from `nameOfHolder`) | `additionalPersonalDetails` |
| `additionalDocumentDetails` | same |
| `optionalDetails` (`OptionalDetails`: `content`, `fields` as `List<TagValue>`) | `optionalDetails` |
| `securityInfos` | `securityOptions.securityInfos` |
| `activeAuthenticationPublicKeyInfo` | same |
| `personsToNotify` (`List<PersonToNotify>`) | `personsToNotify.persons` |
| `debugEvents` (`List<DebugEvent>`: `timestampMillis`, `message`) | `debugInfo.events` |

`DocumentImage` has `width` and `height` instead of `size`, plus `displayable`. The MRZ records
are `Td1MachineReadableZone`, `Td2MachineReadableZone` and `Td3MachineReadableZone` with the
[MachineReadableZone](#machinereadablezone) fields. Every element is one `MrzElement` (`value`,
`raw`, `positions`, plus `checkDigit` and `date` where the element has them), names are
`MrzName`, and check digits are `MrzCheckDigit`. They are prefixed `Mrz` so they don't clash with
Flutter's `Element`.
`CertificateInfo.notBefore` and `notAfter` are `DateTime`.

### Enums

| Enum | Kotlin | Swift / JSON | Meaning |
|---|---|---|---|
| `AccessControlProtocol` | `BAC` | `bac` | Basic Access Control. |
| | `PACE` | `pace` | Password Authenticated Connection Establishment. |
| `PaceMapping` | `GENERIC_MAPPING` | `genericMapping` | PACE Generic Mapping. |
| | `INTEGRATED_MAPPING` | `integratedMapping` | PACE Integrated Mapping. |
| | `CHIP_AUTHENTICATION_MAPPING` | `chipAuthenticationMapping` | PACE-CAM: access control that also authenticates the chip. |
| `DataStatus` | `AUTHENTICATED` | `authenticated` | Passive Authentication passed: signature, hashes and chain to a trusted CSCA. |
| | `DENIED` | `denied` | The SOD signature, a hash or the certificate chain is invalid. |
| | `AUTHORITY_CERTIFICATES_NOT_PROVIDED` | `authorityCertificatesNotProvided` | The SOD signature and hashes were checked but no trusted CSCA matched the signer. |
| `DataProtocol` | `PASSIVE_AUTHENTICATION` | `passiveAuthentication` | Passive Authentication (9303-11 §5.1). |
| `HashStatus` | `VALID` | `valid` | The data group matches its SOD hash. |
| | `INVALID` | `invalid` | It does not, or it was read but the SOD has no hash for it. |
| | `NOT_READ` | `notRead` | Listed in the SOD but not read (access denied or absent). |
| `ChipStatus` | `AUTHENTICATED` | `authenticated` | The chip proved possession of its private key. |
| | `DENIED` | `denied` | The proof failed: PACE-CAM did not verify, EF.CardSecurity is not authentic, or Active Authentication failed. |
| | `NOT_SUPPORTED` | `notSupported` | The chip offers no chip authentication, or no key was available to check it. |
| `ChipProtocol` | `PACE_CHIP_AUTHENTICATION_MAPPING` | `paceChipAuthenticationMapping` | PACE-CAM. |
| | `CHIP_AUTHENTICATION` | `chipAuthentication` | Chip Authentication v1 (§6.2). |
| | `ACTIVE_AUTHENTICATION` | `activeAuthentication` | Active Authentication (§6.1). |
| `ImageFormat` | `JPEG` | `jpeg` | JPEG. |
| | `JPEG2000` | `jpeg2000` | JPEG 2000; `png` holds a rendering. |
| | `PNG` | `png` | PNG. |
| | `WSQ` | `wsq` | WSQ fingerprint image; not displayable. |
| | `UNKNOWN` | `unknown` | Not recognised. |
| `TravelDocumentType` | `TD1` | `td1` | 3 lines of 30. |
| | `TD2` | `td2` | 2 lines of 36. |
| | `TD3` | `td3` | 2 lines of 44. |
| `ElementaryFileId` | `COM`, `SOD` | `com`, `sod` | EF.COM, EF.SOD. |
| | `DG1` … `DG5`, `DG7` … `DG16` | `dg1` … `dg5`, `dg7` … `dg16` | Data groups (no DG6). |
| `ReadErrorKind` | `READING_DATA_GROUPS` | `readingDataGroups` | Reading the data group files failed. |
| | `PARSE_MASTER_FILE` | `parseMasterFile` | A mandatory file (EF.COM or DG1) could not be parsed. |
| | `UNKNOWN` | `unknown` | Anything else, e.g. an unexpected transport error. |

`ReadErrorKind` has no JSON form; the React Native and Flutter errors do not carry it.

### Errors

#### ReadError

Kotlin `ReadException`, Swift `ReadError`.

| Variant | Fields | When |
|---|---|---|
| `InvalidArgument` | `reason: String` | Bad input from the caller: a malformed access key, a challenge that is not 8 bytes, unloadable authority certificates, MRZ lines `parseMrz` cannot parse, or a scan already in progress on a native scanner. Nothing was sent to the chip. |
| `AccessControl` | `reason: String`, `debugInfo: DebugInfo` | BAC or PACE failed: usually a wrong MRZ or CAN. Also a CAN on a document without PACE. |
| `ChipAuthentication` | `reason: String`, `debugInfo: DebugInfo` | Chip Authentication failed after the chip offered it. The chip may be cloned. |
| `NotConnected` | `reason: String`, `debugInfo: DebugInfo` | The tag left the field, a command timed out, an I/O error, or the session ended (iOS session timeout, connect failure). |
| `Read` | `kind: ReadErrorKind`, `reason: String`, `debugInfo: DebugInfo` | The chip answered, but reading or parsing failed: mandatory DG1/DG2 denied or missing, EF.COM or DG1 unparseable, a secure messaging error while reading, or an unexpected transport error (`kind = unknown`). |
| `Cancelled` | `debugInfo: DebugInfo` | `cancel()` was called, the user dismissed the iOS NFC sheet or the Android scan sheet (Cancel, Back), or the calling coroutine/task was cancelled (iOS; on Android coroutine cancellation throws `CancellationException`). |
| `NfcUnavailable` | `reason: String` | Android: the device has no NFC or it is off. iOS: NFC reading is not available, or the app lacks the NFC entitlement / Info.plist entries (CoreNFC security violation). |

Per-platform codes:

| Core | Kotlin | Swift | React Native `code` | Flutter `EmrtdErrorCode` |
|---|---|---|---|---|
| `InvalidArgument` | `ReadException.InvalidArgument` | `ReadError.InvalidArgument` | `invalid_argument` | `invalidArgument` |
| `AccessControl` | `ReadException.AccessControl` | `ReadError.AccessControl` | `access_control` | `accessControl` |
| `ChipAuthentication` | `ReadException.ChipAuthentication` | `ReadError.ChipAuthentication` | `chip_authentication` | `chipAuthentication` |
| `NotConnected` | `ReadException.NotConnected` | `ReadError.NotConnected` | `not_connected` | `notConnected` |
| `Read` | `ReadException.Read` | `ReadError.Read` | `read` | `read` |
| `Cancelled` | `ReadException.Cancelled` | `ReadError.Cancelled` | `cancelled` | `cancelled` |
| `NfcUnavailable` | `ReadException.NfcUnavailable` | `ReadError.NfcUnavailable` | `nfc_unavailable` | `nfcUnavailable` |
| (binding only) | | | `busy` | `busy` |
| (binding only) | | | | `unknown` |

Binding-specific mappings:

- `busy`: `readDocument` called while a read is running.
- `invalid_argument`: no MRZ key or CAN in the options, a challenge that is not valid base64
  (React Native), or authority certificates that cannot be loaded.
- Android: no foreground activity, or an `IllegalStateException` from the NFC adapter →
  `nfc_unavailable`; coroutine cancellation → `cancelled`; any other exception → `read`.
- iOS: `CancellationError` → `cancelled`; any error that is not a `ReadError` → `nfc_unavailable`.
- Flutter: a code it does not know → `unknown`.
- Errors from the core carry `reason`, `kind` and the debug log in React Native (`EmrtdError`)
  and Flutter (`EmrtdException`), passed through `readErrorToJson`. Errors raised by the binding
  itself (`busy`, a missing activity) have only `code` and `message`.

#### TransportError

Kotlin `TransportException`, Swift `TransportError`. Thrown by a `CardTransport`.

| Variant | Fields | Throw when | Read fails with |
|---|---|---|---|
| `TagLost` | | The tag left the field or the connection closed. | `NotConnected` |
| `Timeout` | | The chip did not answer in time. | `NotConnected` |
| `Cancelled` | | The host cancelled the read. | `Cancelled` |
| `Io` | `detail: String` | Any other link error. | `NotConnected` |
| `Unexpected` | `detail: String` | A bug or an unknown failure. | `Read` with `kind = unknown` |

Any other exception thrown from `transceive` is treated as `Unexpected`.

### ReadOutcome

A flat summary of a read for analytics, built by `readOutcome(document, error, durationMs)`. No
personal data beyond issuing state and document code.

| Property | Type | Meaning |
|---|---|---|
| `resultStatus` | `String` | `success` or `failure`. |
| `resultError` | `String?` | On failure: `invalid_argument`, `access_control`, `chip_authentication`, `connection` (for `NotConnected`), `reading_data_groups`, `parse_master_file`, `unknown` (for `Read` of kind `unknown`), `cancelled` or `nfc_unavailable`. |
| `accessControlProtocol` | [`AccessControlProtocol?`](#enums) | From the document. |
| `paceMapping` | [`PaceMapping?`](#enums) | From the document. |
| `chipAuthenticationStatus` | [`ChipStatus?`](#enums) | From the document. |
| `chipAuthenticationProtocol` | [`ChipProtocol?`](#enums) | From the document. |
| `dataAuthenticationStatus` | [`DataStatus?`](#enums) | From the document. |
| `mrzIssuingState` | `String?` | MRZ issuing state. |
| `mrzDocumentCode` | `String?` | MRZ document code. |
| `dataGroups` | [`[ElementaryFileId]`](#enums) | Files present on the chip (read or access denied). |
| `durationMs` | `u64` | The duration passed in. |

`resultError` values differ from the React Native error codes: `connection` instead of
`not_connected`, and `read` split by kind.

## License

Proprietary. See [LICENSE](LICENSE).
