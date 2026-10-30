import DerivedKeysUI

struct WrongBindingRoot {
    var text = "text"
}

@MainActor
func invalidBindingRoot(_ cache: SizeCache<Int>) {
    // expected-error: cannot convert value of type
    let _: SizeCacheBinding<WrongBindingRoot> = cache.bound(to: \WrongBindingRoot.text)
}
