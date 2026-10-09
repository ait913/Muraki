---
title: flutter build ios --simulator --no-codesign は Keychain 書き込みが -34018 で死ぬ (shot driver の live が LaunchScreen で止まる) / Riverpod 3 は build 中に他 provider を変更すると AsyncError
category: gotcha
tags: [flutter, ios-simulator, codesign, keychain, flutter_secure_storage, shot-driver, riverpod]
created: 2026-10-09
project: bloom
sources:
  - sessions/2026-10-09-acd2f2e3.md
  - projects/bloom/docs/DEVELOPMENT.md
---

## Context

bloom の shot driver (`shot.json` で画面を再現して `simctl io screenshot`) で `mode: "live"` (dev1 に login-as) だけがネイティブの LaunchScreen から進まなかった。demo モードと通常起動は動く。サーバーには `POST /dev/login-as` 200 まで届いていた。

## What

1. **`--no-codesign` でビルドしたシミュレータ app は linker 署名のみ (`codesign -dv` → `flags=0x20002(adhoc,linker-signed)`) になり、`SecItemAdd` / `SecItemDelete` が `-34018 errSecMissingEntitlement` で失敗する** (読み `SecItemCopyMatching` は通る)。`completeSignIn` → `FlutterSecureStorage.write` の例外が `applyShotConfig` → `main()` まで伝播し、`runApp` に到達しないので LaunchScreen のまま。`--no-codesign` を外すだけで直る (adhoc 署名、entitlements は空 dict のままでよい)。
2. 起動のたびに `clearTokens` も -34018 で失敗して Crashlytics に残り、`auth_cleanup_pending` が消えず毎回 cleanup を繰り返す (同根)。
3. **Riverpod 3.4: `FutureProvider` の build の同期区間で `ref.read(other.notifier).method()` を呼ぶと debug assert「Providers are not allowed to modify other providers during their initialization」で provider が `AsyncError` になる** (release では出ない)。bloom の demo `hero_beacon` が「読み込み中」のままピンが出なかった原因 (`map_state.dart` の `seedFromSnapshot(demoBeaconPins())`)。`Future.microtask` に逃がす。

## Why

`--no-codesign` = `CODE_SIGNING_ALLOWED=NO` で codesign ステップが省かれ、シミュレータの securityd は linker 署名 app の Keychain 書き込みを拒む。以前 live が撮れていたのは、その時点のシミュレータが既にサインイン済みで `loginAsAccount` をスキップしていたため (`dev_entry.dart` の `if (!current.signedIn || current.demoMode)`)。

## How to apply

- シミュレータビルドは `flutter build ios --simulator --flavor dev --dart-define-from-file=env/dev.json` (`--no-codesign` を付けない。ビルド時間は変わらない)。`docs/DEVELOPMENT.md` / 設計 doc の手順は 2026-10-09 に置換済み。
- shot driver の適用失敗で起動を止めない: `main.dart` の `applyShotConfig` は try/catch + `DebugLog.instance.record` (2026-10-09 適用)。
- LaunchScreen から進まない症状は「Dart の未捕捉例外で `runApp` 前に死んでいる」をまず疑い、`xcrun simctl spawn <udid> log stream --predicate 'process == "Runner"' --style compact` で `Unhandled Exception` を探す。
- Riverpod 3 で provider の build から他 provider を変更したいときは `await` の後か `Future.microtask`。
