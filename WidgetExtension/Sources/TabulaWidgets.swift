// Widget extension (target/product `TabulaWidgets`). Phase 4 A: the Phase 0 hello widget is replaced by *Now & Next*;
// Phase 4 B adds Today / Homework / Next exam. COMPILED on both paths (xtool on WSL; XcodeGen in CI).
// xtool packs this as a Foundation NSExtension (PlugIns/TabulaWidgets.appex, entry point
// _NSExtensionMain); ExtensionKit-style extensions are NOT supported by xtool (issue #138).
// APIs (docs checked): WidgetBundle, Widget (iOS 14).
import SwiftUI
import WidgetKit

@main
struct TabulaWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
        // Owned by the notifications agent (WidgetExtension/Sources/AlarmLiveActivity.swift).
        AlarmLiveActivity()
    }
}
