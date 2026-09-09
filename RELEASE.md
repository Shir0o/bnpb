# BNPB Releases

All notable changes to the BNPB project are documented here.

## [1.2.1](https://github.com/Shir0o/bnpb/compare/v1.2.0...v1.2.1) (2026-09-09)


### Bug Fixes

* reconcile prayer list sync across devices and fix json export import ([#264](https://github.com/Shir0o/bnpb/issues/264)) ([5c01af6](https://github.com/Shir0o/bnpb/commit/5c01af6a77d40707cfd43861bbb08b1088764dcc))

## [1.2.0](https://github.com/Shir0o/bnpb/compare/v1.1.0...v1.2.0) (2026-09-07)


### Features

* add clear button to home page search bar ([84b8019](https://github.com/Shir0o/bnpb/commit/84b80198b1b031b9d4cb1c4e4ce5d15ddf3d0fbc))
* Add inline contact creation within selection sheet on prayer list page ([#221](https://github.com/Shir0o/bnpb/issues/221)) ([5af6347](https://github.com/Shir0o/bnpb/commit/5af6347cb218f726a6bf846fd5a37e6820820938))
* add interaction de-duplication in settings ([#212](https://github.com/Shir0o/bnpb/issues/212)) ([0325318](https://github.com/Shir0o/bnpb/commit/0325318ef4c23d36b776358f8be43cc6417d35c1))
* add macOS contacts grid view ([a111d10](https://github.com/Shir0o/bnpb/commit/a111d104fe6923acaba6828b46eb004cdbdb8eb0))
* Add notes to contact, update DB schema (v13), and enhance export/import ([b17bb13](https://github.com/Shir0o/bnpb/commit/b17bb131774e8ebef1e9a844c98a6ad65e3b6fc6))
* add RepaintBoundary to PeopleCard for performance ([5c32af0](https://github.com/Shir0o/bnpb/commit/5c32af047d97e089e3d2110305375f0bc8f6d9b9))
* add stage confirm system and period review ([#248](https://github.com/Shir0o/bnpb/issues/248)) ([78eb72e](https://github.com/Shir0o/bnpb/commit/78eb72e6fb97df305b5365ba68b35ae2e6c0f9b7))
* Add suggested contacts with ranking and animation ([42714c7](https://github.com/Shir0o/bnpb/commit/42714c784352ddc9afa9f1e76ca483ebc45b4940))
* **android:** add release signing configuration with debug fallback ([66dd172](https://github.com/Shir0o/bnpb/commit/66dd172c04e7fb236255b8f5ecd9d336a3b0072f))
* **assets:** add new app icons for all platforms ([f1dd1d2](https://github.com/Shir0o/bnpb/commit/f1dd1d2d7e0b70d12d4b82b1fbc5f17b11c7c709))
* Auto dial-back interaction start time based on duration input ([2e834ac](https://github.com/Shir0o/bnpb/commit/2e834ace19df9c6de6e57cc753ef1933d8ee6505))
* Auto dial-back interaction start time based on duration input ([18f3d5b](https://github.com/Shir0o/bnpb/commit/18f3d5b6c41661155626436595f0caf5d747a995))
* auto-dismiss prayer list snackbar on pop/navigation and add AI suggestions setting ([#214](https://github.com/Shir0o/bnpb/issues/214)) ([be66635](https://github.com/Shir0o/bnpb/commit/be666355af55f3cf20c4d84b3f95e7e5991baee5))
* **db:** add clearAllData maintenance method to DBHelper ([8182617](https://github.com/Shir0o/bnpb/commit/81826175c109dddc0a3e989b9bdaa9cd049ad96b))
* disable app bar scroll overlay globally, customize font size in settings, scale up title fonts, and resize header buttons ([#232](https://github.com/Shir0o/bnpb/issues/232)) ([a46f903](https://github.com/Shir0o/bnpb/commit/a46f90310a47dd8e62af136928db438e7f22eab9))
* **docs,db,sync:** refactor database layer to DAOs, finalize sync, and add project documentation ([8dab1a8](https://github.com/Shir0o/bnpb/commit/8dab1a8d97203ec44f38fc842a8f1fe65d16251c))
* Enable Cmd+R refresh on macOS, fix sync bugs ([69d03bd](https://github.com/Shir0o/bnpb/commit/69d03bd58b83054f86b006ad8a77b9d953612fc4))
* enhance export UI with animations and fix spacing ([ba67f5b](https://github.com/Shir0o/bnpb/commit/ba67f5b7cb70c0dcbca81c904d2b5fa234c9a8e1))
* gate exact alarm permission behind opt-in ([a52128a](https://github.com/Shir0o/bnpb/commit/a52128ad64cdb8dbf7486496f9de05c6c7ff9270))
* hide top bar on scroll down across all pages ([#234](https://github.com/Shir0o/bnpb/issues/234)) ([0c36112](https://github.com/Shir0o/bnpb/commit/0c36112f03a3c463270f19aac6dce3b4358567e0))
* implement custom settings switch toggles for crisp utility design ([#237](https://github.com/Shir0o/bnpb/issues/237)) ([9d8c3d3](https://github.com/Shir0o/bnpb/commit/9d8c3d318b56c5921391d70ad1918ea475c9baef))
* implement dark mode, group count badges, and gesture-based multi-select ([#236](https://github.com/Shir0o/bnpb/issues/236)) ([1405e3d](https://github.com/Shir0o/bnpb/commit/1405e3d0b422ada3f5337aa2856b53a44a38da2f))
* Implement data synchronization logic with a new SyncCoordinator service for managing data export, import, and merging. ([bec0ed4](https://github.com/Shir0o/bnpb/commit/bec0ed4844ba28c9ecdbb4954662ddeec4313b92))
* implement Google Drive sync, force light theme on MacOS, and fix settings scroll jump ([35a7249](https://github.com/Shir0o/bnpb/commit/35a724915e8a5d39ea6a9c311b9c14a19f8261c6))
* Implement interaction de-duplication dry run & preview confirmation dialog ([#215](https://github.com/Shir0o/bnpb/issues/215)) ([08507a6](https://github.com/Shir0o/bnpb/commit/08507a6d75e8e2b927c2a293e6b8f32720fd652a))
* implement macOS contact details design ([a8582fe](https://github.com/Shir0o/bnpb/commit/a8582fe32d596dcfad7c76d9e20530e5bba16873))
* implement Ready to log interaction suggestion card from BNPB Prototype ([#247](https://github.com/Shir0o/bnpb/issues/247)) ([d34ecd5](https://github.com/Shir0o/bnpb/commit/d34ecd5b309ba2a9d0b6c8a92cfc52631ff36f55))
* Implement safe sync on app open/close with integrity checks ([c551316](https://github.com/Shir0o/bnpb/commit/c5513168402a43e18ff6683d7fd00c5da77ca415))
* implement scroll anchoring, bulk select location editing, and detailed deduplication dry run comparison ([#235](https://github.com/Shir0o/bnpb/issues/235)) ([eca246e](https://github.com/Shir0o/bnpb/commit/eca246e8323e7e668eb886172476788eb8eb81eb))
* improve backup/restore UX and robust Google Sign-In ([16cbd84](https://github.com/Shir0o/bnpb/commit/16cbd84f65bf5b8dabaab0e1a54c8e01384f8050))
* Improve sync/export for shared prayer requests and polish UI ([4c52e95](https://github.com/Shir0o/bnpb/commit/4c52e95ae3382242d8ee22e6021a132eaad9f597))
* integrate Gemini AI for smart suggestions with persistent caching ([47913bf](https://github.com/Shir0o/bnpb/commit/47913bfdb4cc52c75ed6007bb02702fce6201b24))
* macOS Contacts Grid View ([2d700b0](https://github.com/Shir0o/bnpb/commit/2d700b0b01ac25f0d48fb97e243ad9cf06579ee7))
* **macos:** add Select Contact button and integrate Prayer List data into Active Contacts view ([505ed58](https://github.com/Shir0o/bnpb/commit/505ed58239d1418a17980e47ed3d040c27f7b5d3))
* **macos:** implement marking prayer request as answered ([e80fdf1](https://github.com/Shir0o/bnpb/commit/e80fdf1d5ec7bbac7f45c10ee490fff04469c183))
* **macos:** implement Prayer Diary page and integrate into shell ([55f161d](https://github.com/Shir0o/bnpb/commit/55f161de4d9858db58dc02c4065996c091780cf2))
* **macos:** update Prayer Diary UI with inline editing and Stitch design ([da07941](https://github.com/Shir0o/bnpb/commit/da0794149cfce7b215bccabbe06ed82de427e427))
* **macos:** update settings UI to match Stitch design and fix Google Sign-In credentials ([9a5d54d](https://github.com/Shir0o/bnpb/commit/9a5d54d59e7a440d0df0775d912608eabdcebfd2))
* Optimize ContactSearchService._normalize RegExp compilation ([a03a053](https://github.com/Shir0o/bnpb/commit/a03a053e5ae15ba63fc635e07001c1387e665428))
* Optimize HomePage data loading and reduce rebuilds ([d1bde09](https://github.com/Shir0o/bnpb/commit/d1bde0912dba6fee179554bd4919e32909a53828))
* Optimize image memory usage in ContactDetailsPage ([434be9b](https://github.com/Shir0o/bnpb/commit/434be9b38e46fcc825ba3e235a898799aafe75be))
* Optimize memory for PeopleCard recognition photos ([ba53f1f](https://github.com/Shir0o/bnpb/commit/ba53f1f0b011e9e51614494a75d2ac07ae5f4b92))
* Optimize SmoothExpansionTile with RepaintBoundary for silky animations ([7214bd6](https://github.com/Shir0o/bnpb/commit/7214bd6f4f7c3e0797a3aba79db7223508f7a604))
* optimize sync and improve prayer list consistency ([d262bd3](https://github.com/Shir0o/bnpb/commit/d262bd346c96726fbbdb25c481e0a6a2c97f3eaa))
* optimize sync and improve prayer list consistency ([203bbc0](https://github.com/Shir0o/bnpb/commit/203bbc0cf11f6d8cc659e085167cae4e674dcc00))
* Parallelize Google Drive sync downloads and uploads ([cac3e52](https://github.com/Shir0o/bnpb/commit/cac3e52922866ab52b6bdb7045386ec4922b07d1))
* **perf:** Offload contact search to isolate ([d2dcef3](https://github.com/Shir0o/bnpb/commit/d2dcef3cc60c5ebc40fd7e598dbd94411e452eef))
* **ready-to-log:** add per-feature gate for scripture-ref AI fallback ([8cbc39f](https://github.com/Shir0o/bnpb/commit/8cbc39f122f46a1cda8d0bc58efecf5cf50e0368))
* **ready-to-log:** add per-feature toggle to AI settings ([d3a88f9](https://github.com/Shir0o/bnpb/commit/d3a88f9f76615ebc8ef1d2314b7e195689cde551))
* **ready-to-log:** add ScriptureRef.tryAdvance with expanded regex set ([8dd43b4](https://github.com/Shir0o/bnpb/commit/8dd43b47e4e2f059c2d37308f5f233268a6d4c8f))
* **ready-to-log:** add ScriptureRefAdvancementPipeline ([6a9443f](https://github.com/Shir0o/bnpb/commit/6a9443f06c824fa2658d6574a709554aaae3adfd))
* **ready-to-log:** add ScriptureRefAdvancementService ([bc4e42b](https://github.com/Shir0o/bnpb/commit/bc4e42b387e607d09e2d1ca9b3bda4c1344d3928))
* **ready-to-log:** wire home_page card to scripture-ref pipeline ([e7a87d7](https://github.com/Shir0o/bnpb/commit/e7a87d7a20673c1d85f6eb13e217bb62e844d48a))
* redesign home page suggestion card with priority badges and quick interaction logging ([#245](https://github.com/Shir0o/bnpb/issues/245)) ([f2aaaf5](https://github.com/Shir0o/bnpb/commit/f2aaaf59870756933d52c34b4ae944a1c7cc2760))
* Refine follow-up suggestion logic and add heuristics fallback ([#217](https://github.com/Shir0o/bnpb/issues/217)) ([f1c6cff](https://github.com/Shir0o/bnpb/commit/f1c6cff4d875a33d98e58be64576fe59803a70f0))
* **release:** set up automated release to google internal testing track ([#260](https://github.com/Shir0o/bnpb/issues/260)) ([7136d81](https://github.com/Shir0o/bnpb/commit/7136d811d3ba652023d9e3196fbeb110a578198c))
* replace interaction categories with notes ([778236d](https://github.com/Shir0o/bnpb/commit/778236dcf0d579f3277f185e9ac5b39481e19ebb))
* replace loading spinner with skeleton loader ([55e15e9](https://github.com/Shir0o/bnpb/commit/55e15e9580eda395db196ab7ff20b72f3a939f56))
* smooth home page animations, refined skeleton loading, and optimized closing behavior ([0c592e4](https://github.com/Shir0o/bnpb/commit/0c592e417c6d1d6bc3c6038a534b9f193951b293))
* sort prayer diary by status (pending first) and date ([bc15954](https://github.com/Shir0o/bnpb/commit/bc159541f0809e34b9259442b5f926dd05bbf7fd))
* support manual occurred time entry ([00299e3](https://github.com/Shir0o/bnpb/commit/00299e3516a71cd1a334b1ca8063cafe4203d2c2))
* support manual occurred time entry ([7c5f7e1](https://github.com/Shir0o/bnpb/commit/7c5f7e1420db8514a2279329ab584a030e619a80))
* Support multiple contacts for prayer requests and polish UI ([3523b9c](https://github.com/Shir0o/bnpb/commit/3523b9ce579e04f54636744810c0de9a27006410))
* **sync:** optimize Google Drive sign-in flow and improve sync reliability ([dd8ba3e](https://github.com/Shir0o/bnpb/commit/dd8ba3e720a729cb365febd81c25c4e1508959ed))


### Bug Fixes

* **android:** add missing notification permissions and boot receiver ([5c49c4f](https://github.com/Shir0o/bnpb/commit/5c49c4f2a89c4b33e8ea04ac9e2407bee7194ab9))
* **db:** use constant default value for prayer_lists.updatedAt migration ([7fb65b4](https://github.com/Shir0o/bnpb/commit/7fb65b46b06093ccac69eb22a116460b7d88748f))
* disable disappearing headers on prayer screens, add prayer list backup/restore & prefill quick-log ([#246](https://github.com/Shir0o/bnpb/issues/246)) ([0a850ff](https://github.com/Shir0o/bnpb/commit/0a850ff580389a48d3e20081cff889bc91263394))
* explicitly define surfaceTint in ColorSchemes to prevent fallback to green brand color ([#242](https://github.com/Shir0o/bnpb/issues/242)) ([45b9eb8](https://github.com/Shir0o/bnpb/commit/45b9eb8dd323dfbdc39a986dd1c115a698635ffe))
* improve Google Drive auth robustness and update CI docs ([baa3395](https://github.com/Shir0o/bnpb/commit/baa33953b2345918c530518ff490c1b0fe536062))
* **macos:** lazy load Google Drive API to prevent double keychain access ([feb1355](https://github.com/Shir0o/bnpb/commit/feb135590226f1638b902fe30deb6a7f5fb33309))
* **notifications:** declare ScheduledNotificationReceiver in AndroidManifest ([#253](https://github.com/Shir0o/bnpb/issues/253)) ([699b2db](https://github.com/Shir0o/bnpb/commit/699b2db04e95ff6ca0c60e524b13dac6e12ff21b))
* paginate Google Drive sync listing and harden imports against missing contacts ([#244](https://github.com/Shir0o/bnpb/issues/244)) ([02f846d](https://github.com/Shir0o/bnpb/commit/02f846d3f5bedae5f5bc8e29c3ed81710edb04f6))
* reconnect orphaned per-contact/category reminder overrides ([#241](https://github.com/Shir0o/bnpb/issues/241)) ([dfe3b5d](https://github.com/Shir0o/bnpb/commit/dfe3b5d0d88da207776afe8add5db6fafa7e3b86))
* **reminders:** fallback to inexact scheduling when exact alarm permission is missing ([8f522b4](https://github.com/Shir0o/bnpb/commit/8f522b494d4bc1aaefbf7e2ac97dbb32ba7d0910))
* resolve contact name for newly added participants in interaction sheet ([ed6d4b5](https://github.com/Shir0o/bnpb/commit/ed6d4b51d1697043dc46cdb0e5dc94ef803060e2))
* resolve contact name for newly added participants in interaction sheet ([dd31ec8](https://github.com/Shir0o/bnpb/commit/dd31ec8098dd4a8265f7dbd6243f9feacf537816))
* resolve Google Fonts crash and silence unhandled sign-in exceptions ([5390ec6](https://github.com/Shir0o/bnpb/commit/5390ec619e1cfb146c7fa3a6e53bc185895ef50f))
* resolve Google Sign-In flashes and sync hangs ([3172cbf](https://github.com/Shir0o/bnpb/commit/3172cbfcfd23d3e935e0da5d70af8f2453b0a10d))
* resolve interaction data loss and database migration error ([ea841fd](https://github.com/Shir0o/bnpb/commit/ea841fd88458ab59fc7371c0256712defb439541))
* resolve ListTile layout assertions and SQLite double-quoted literal warnings ([#216](https://github.com/Shir0o/bnpb/issues/216)) ([7a10704](https://github.com/Shir0o/bnpb/commit/7a107045460961cb404ec63f762940de8ccb7270))
* resolve sync deletion issues, prevent concurrent syncs, and improve sync stability ([c52b01e](https://github.com/Shir0o/bnpb/commit/c52b01e0c3fe56de14d8ffc1a23e282e6f3fedc5))
* **sync:** Preserve explicit timestamps on contact sync and enforce UTC across database writes ([73f1ce1](https://github.com/Shir0o/bnpb/commit/73f1ce1b23387e657a1e87b1ae968f633b50d7d8))
* **ui:** prevent modal bottom sheets from overlapping system status bar ([ba81718](https://github.com/Shir0o/bnpb/commit/ba81718231b93eeca718f9aec42d55cc6ada427d))
* update desugar_jdk_libs to 2.1.4 to fix build error ([1970d53](https://github.com/Shir0o/bnpb/commit/1970d53b91a01dc20d4120dba81698af9e0551a4))
* Update macOS deployment target to resolve build errors related to `file_picker` module. ([0cd1f46](https://github.com/Shir0o/bnpb/commit/0cd1f465c3fd896eb03a0dfd187bfe5cee11609d))


### Performance

* Add RepaintBoundary to SmoothExpansionTile ([335127b](https://github.com/Shir0o/bnpb/commit/335127b64c7dd60280faf2b22ebc33508a5fc771))
* batch fetch and merge interactions in SyncCoordinator ([#251](https://github.com/Shir0o/bnpb/issues/251)) ([3125ae8](https://github.com/Shir0o/bnpb/commit/3125ae820123ec74ae3ed65df783e7fc9061e29b))
* cache DateFormat instances to reduce build loop overhead ([91f8207](https://github.com/Shir0o/bnpb/commit/91f820799ded021cc78bc849786656a7cb8d3ef7))
* optimize contact parsing by passing objects directly ([daee619](https://github.com/Shir0o/bnpb/commit/daee6191ba8b8d363b8a270d273ac8e633ef696a))
* optimize contact search by pre-calculating trigrams ([caa3baf](https://github.com/Shir0o/bnpb/commit/caa3bafffb80caf7ebe20319b5a2de8c05170c17))
* optimize interaction orphan removal ([4d818e7](https://github.com/Shir0o/bnpb/commit/4d818e7f0728328203b9b8993fa1888b5f3e0f13))
* optimize interaction sorting and access logic ([84c37e0](https://github.com/Shir0o/bnpb/commit/84c37e0a8df22ac574246928f803221b7da68ba1))
* Optimize Log Interaction sheet open speed by reusing contacts ([eae2915](https://github.com/Shir0o/bnpb/commit/eae2915b80f91988b97d6d9d0c2b456297d0320a))
* optimize redundant list processing in Contact and Interaction models ([56f559f](https://github.com/Shir0o/bnpb/commit/56f559ff6544ac27b36e3646ab793ae47a5bf1c1))
* optimize SkeletonLoader with RepaintBoundary ([5bf7b39](https://github.com/Shir0o/bnpb/commit/5bf7b39786afce5c4ec44646b9e974c79a26e4a0))
* optimize SmoothExpansionTile build cycle ([eee597c](https://github.com/Shir0o/bnpb/commit/eee597ca90c0438f7c8ea1f70b957d32ee8cd308))
* optimize startup by moving heavy tasks to background ([b3dee45](https://github.com/Shir0o/bnpb/commit/b3dee4578a309633a4cd8a7e1c00580cc8663e1a))
* Refactor HomePage to use CustomScrollView and SliverList ([3813817](https://github.com/Shir0o/bnpb/commit/3813817f11750a19072317f7ef2ea51c0826b8eb))
* replace IntrinsicHeight with Stack in contact timeline ([2dcb166](https://github.com/Shir0o/bnpb/commit/2dcb166f4044b6e86fdaca4907c03c2290fe9352))
* replace IntrinsicHeight with Stack in contact timeline ([eca5942](https://github.com/Shir0o/bnpb/commit/eca594272b0addd6afd6837a1d0f7690210c5d15))
* **sync:** optimize Google Drive sync to only download latest files ([8261835](https://github.com/Shir0o/bnpb/commit/8261835622de6332256f8907752feda4b05cf89a))
* **ui:** optimize SettingsPage refresh logic ([56cad7e](https://github.com/Shir0o/bnpb/commit/56cad7e744807c8dd06f877df77805948c5d545a))
* use batch inserts for participant replacement in SyncCoordinator ([495b78a](https://github.com/Shir0o/bnpb/commit/495b78a345cf39a026abf20630f25647f8830e05))
* Use lazy builder in SmoothExpansionTile to reduce HomePage rebuild cost ([31d76a9](https://github.com/Shir0o/bnpb/commit/31d76a91cb47c797f442b381814cf8b398570baa))


### Refactoring

* delete unused reminder_overrides_page.dart ([4090bb3](https://github.com/Shir0o/bnpb/commit/4090bb311a3c8e23d9c466201fe5d213e435b72c))
* simplify PeopleCard by removing detailed recognition and interaction sections. ([c32ebee](https://github.com/Shir0o/bnpb/commit/c32ebeed10d46e40662648855a4d99cc5a7f51b9))

## [1.1.0] - 2026-04-28

### Added
- Google silent sign-in for improved synchronization flow.
- Filter for active follow-up reminders on the analytics page.
- Comprehensive prayer list export/import tests.
- **Intelligent Follow-up Recommendations**: AI-driven suggestions based on interaction gaps, prayer requests, and meeting notes.

### Changed
- Upgraded Google Sign-In to v7.x for enhanced security and reliability.
- Optimized performance for `buildFullExportPayload`.
- Optimized legacy interactions migration in database helper.
- Improved UI state synchronization for Google Sign-In.

### Removed
- Redundant recognition cues, tags, and specialized meeting search to simplify the UI.
- Unused backup and temporary files.
- `speech_to_text` dependency and related voice-capture UI logic.

## [1.0.0] - 2026-03-30

### Added
- Initial release of the BNPB offline-first relationship manager.
- Encrypted storage using SQLCipher and platform-secure key storage.
- Contact management with support for custom fields and interaction history.
- Relationship visualization using graph views.
- Data export in CSV, PDF, and encrypted JSON archive formats.
- Biometric and passcode lock screens.
- Prayer diary and notification scheduling.
- Analytics dashboard with relationship insights.
- Privacy policy and developer guidelines.
