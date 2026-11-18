# TRYON LANKA — Wear it before you buy it.

Android/iOS shopping app for the TRYON LANKA WooCommerce store, built on the
open-source **Label StoreMax** Flutter template (WooSignal, BSD-2-Clause) with
an added **on-device live virtual try-on**.

## What was added on top of StoreMax

| Area | Files |
|---|---|
| Live camera try-on (ML Kit Pose Detection, runs on the phone) | `LabelStoreMax/lib/resources/pages/tryon_page.dart` |
| Garment fit maths (shoulders, hips, angle, smoothing) | `LabelStoreMax/lib/app/tryon/pose_fit.dart` |
| Product calibration from WooCommerce meta | `LabelStoreMax/lib/app/tryon/garment_calibration.dart` |
| Garment drawing (cutout image or built-in silhouette) | `LabelStoreMax/lib/app/tryon/garment_painter.dart` |
| "TRY WITH CAMERA" on product page | `LabelStoreMax/lib/resources/widgets/tryon_button_widget.dart` |
| Try-On hub (drawer → Live Try-On) | `LabelStoreMax/lib/resources/pages/tryon_hub_page.dart` |
| Sinhala + English only | `LabelStoreMax/lang/si.json`, `lang/en.json` |
| WordPress plugin for try-on settings | `wordpress-plugin/tryon-lanka-tryon/` |
| Automatic APK build | `.github/workflows/build-apk.yml` |
| Tests | `LabelStoreMax/test/tryon_fit_test.dart` |

## Getting an installable APK

Every push to `8.x` runs **Actions → Build TRYON LANKA APK**. When it finishes,
the APK is attached to a pre-release under **Releases** (`build-N`). Open that
page on the phone, download the `.apk`, and allow "Install unknown apps".

The test APK is signed with the debug key. For Play Store, add a release
keystore (see "Release signing" below).

## Connect the real store (required for products/cart/checkout)

StoreMax talks to WooCommerce through WooSignal, so no WooCommerce admin
consumer secret is ever put in the app.

1. Create a free account at https://woosignal.com and connect the TRYON LANKA
   WooCommerce site (install the WooSignal plugin on WordPress as instructed).
2. Copy the app key from the WooSignal dashboard.
3. In GitHub: **Settings → Secrets and variables → Actions → New repository
   secret**
   - `WOOSIGNAL_APP_KEY` = your WooSignal app key
   - `STORE_URL` = `https://your-store.lk` (optional)
4. Re-run the workflow. The new APK loads the real catalogue.

Theme colours, logo, currency (LKR), payment gateways and menus are configured
in the WooSignal dashboard for the app. Suggested palette: Black `#111111`,
White `#FFFFFF`, Cream `#F7F5F0`, Gold `#C8A878`, Text `#252525`.

Customer login/registration uses the **WP JSON API** WordPress plugin (5.x),
as documented by WooSignal.

## Enabling try-on for a product

1. Upload `wordpress-plugin/tryon-lanka-tryon` to `wp-content/plugins/` and
   activate **TRYON LANKA Try-On Settings**.
2. Edit a T-shirt/shirt product → **Live Try-On** tab:
   - tick *Enable live try-on*
   - paste an **https** URL of a transparent, front-facing garment cutout
     (PNG/WebP, collar at the top edge, no model photo)
   - adjust width ratio / offsets if the overlay sits too wide or low.
3. The values are saved as public product meta (`tryon_*`) and returned in the
   normal WooCommerce product `meta_data`. Read-only endpoint for other uses:
   `GET /wp-json/tryon-lanka/v1/product/{id}` (variations inherit the parent).

Products without settings show "Try-On not available" and offer demo garments.

## Privacy

- Camera permission is requested only when the user opens Try-On, after a
  privacy notice.
- Pose detection uses Google ML Kit's bundled on-device model. No frames, video
  or body points leave the phone. No OpenAI/Gemini/FASHN/Replicate or any cloud
  inference.
- The camera stops when the screen closes or the app goes to the background;
  the ✕ button is a visible camera stop control.
- A preview photo is made only when the user taps capture; it is saved locally
  or shared only when the user taps Save/Share.
- The overlay is a 2D preview, not a guarantee of fit.

## Release signing (Play Store)

Create a keystore, add it as base64 secret, and change
`android/app/build.gradle` `buildTypes.release.signingConfig`. The App Bundle
(`.aab`) is already built by the workflow. Also change the Firebase config in
`lib/firebase_options.dart` if you use push notifications.

## Testing status

- Unit tests for calibration parsing, fit maths, smoothing and translation
  parity run in CI.
- **Not yet tested on a physical device.** Please check on a low-end, mid-range
  and high-end Android phone: camera permission, live preview, tracking,
  front/back switch, capture/share, and background/foreground.
