import DerivedKeysUI

// expected-error: cannot inherit from non-open class 'SizeDependencies<Int>' outside of its defining module
@MainActor
final class ForgedSizeDependencies: SizeDependencies<Int> {}
