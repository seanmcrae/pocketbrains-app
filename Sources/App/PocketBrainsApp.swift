import SwiftUI
import SwiftData

@main
struct PocketBrainsApp: App {
    private let container: ModelContainer?
    @State private var app: AppModel?

    /// True when this process is hosting a test run. The host must stay
    /// completely inert then: no Metal/CoreMotion (headless CI runners have
    /// no GPU surface) and no ModelContainer (tests build their own stores;
    /// the host must not hold competing SwiftData state).
    private static var isHostingTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    init() {
        if Self.isHostingTests {
            self.container = nil
            self._app = State(initialValue: nil)
        } else {
            let container = Store.sharedContainer // also serves App Intents
            self.container = container
            self._app = State(initialValue: AppModel(context: container.mainContext))
        }
    }

    var body: some Scene {
        WindowGroup {
            if let app, let container {
                RootShell()
                    .environment(app)
                    .modelContainer(container)
                    .preferredColorScheme(.dark)
                    .task {
                        MotionLight.shared.start()
                        app.bootstrap()
                    }
            } else {
                Color.black.ignoresSafeArea() // inert test host
            }
        }
    }
}
