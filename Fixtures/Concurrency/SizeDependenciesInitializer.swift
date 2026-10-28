import DerivedKeysUI

@MainActor
func invalidSizeDependenciesInitializer() {
    // expected-error: initializer is inaccessible due to 'internal' protection level
    _ = SizeDependencies<Int>(depth: 1) { _ in fatalError("Must not compile") }
}
